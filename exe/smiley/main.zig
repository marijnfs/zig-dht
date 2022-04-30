pub const io_mode = .evented; // use event loop

const std = @import("std");

const dht = @import("dht");
const default = dht.default;
const utils = dht.utils;
const timer = dht.timer;
const timer_functions = dht.timer_functions;
const jobs = dht.jobs;
const routing = dht.routing;
const staging = dht.staging;
const db = dht.db;

const c = @import("c.zig");
const Server = dht.Server;
const ID = dht.ID;
const JobQueue = dht.JobQueue;
const ServerJob = dht.ServerJob;

// pub const log_level: std.log.Level = .warn;
var log_file: std.fs.File = undefined;

pub fn time_test() void {
    std.log.info("timer", .{});
}

fn filetest() !void {
    var cwd = std.fs.cwd();
    var dir = try cwd.openDir("test", .{ .iterate = true });

    var walker = try dir.walk(default.allocator);
    while (try walker.next()) |entry| {
        std.log.err("entry {}", .{entry});
    }
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Ignore all non-error logging from sources other than
    // .my_project, .nice_library and .default
    const scope_prefix = "(" ++ switch (scope) {
        .my_project, .nice_library, .default => @tagName(scope),
        else => if (@enumToInt(level) <= @enumToInt(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ "): ";

    const prefix = "[" ++ level.asText() ++ "] " ++ scope_prefix;
    const stderr = log_file.writer();

    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn main() !void {
    log_file = try std.fs.cwd().createFile("log.txt", .{ .intended_io_mode = .blocking });

    var args = try std.process.argsAlloc(default.allocator);
    defer std.process.argsFree(default.allocator, args);
    std.log.info("arg0 {s}", .{args[0]});

    if (args.len < 4) {
        std.log.err("Usage: {s} [username] [localip] [localport] ([remote ip] [remote port])*", .{args[0]});
        return error.MissingArguments;
    }

    try dht.init();

    try c.init();
    defer c.deinit();

    // Add default functions
    try timer.add_timer(10000, timer_functions.expand_connections, true);
    try timer.add_timer(20000, timer_functions.refresh_finger_table, true);
    try timer.add_timer(30000, timer_functions.sync_finger_table, true);
    try timer.add_timer(30000, timer_functions.clear_closed_connections, true);
    try timer.add_timer(60000, timer_functions.detect_self_connection, true);

    default.server = b: {
        const servername = try default.allocator.dupe(u8, args[2]);
        const username = try default.allocator.dupe(u8, args[1]);
        const port = try std.fmt.parseInt(u16, args[3], 0);

        const server = try Server.create(.{ .name = servername, .username = username, .port = port });
        try server.initialize();
        break :b server;
    };

    if (args.len >= 6) {
        const port = try std.fmt.parseInt(u16, args[5], 0);
        const address = try std.net.Address.parseIp(args[4], port);
        try routing.add_address_seen(address);
        try default.server.job_queue.enqueue(.{ .connect = address });
    }

    std.log.info("Spawning Server Thread..", .{});
    try default.server.start();
    try routing.init_finger_table();

    std.log.info("Server ID: {Server ID}", .{utils.hex(&default.server.id)});

    // start timers
    try timer.start_timer_thread();

    std.log.info("Starting Job loop", .{});

    try default.server.wait();
}
