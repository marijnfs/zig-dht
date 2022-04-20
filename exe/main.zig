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

const c = dht.c;
const Server = dht.Server;
const ID = dht.ID;

// pub const log_level: std.log.Level = .warn;

var log_file: std.fs.File = undefined;

pub fn time_test() void {
    std.log.info("timer", .{});
}

fn filetest() !void {
    // var file = try std.fs.cwd().openFile("foo.txt", .{});
    // defer file.close();

    // while (true) {
    //     var buf: [64 << 10]u8 = undefined;
    //     const read = try file.read(&buf);
    //     if (read == 0)
    //         break;

    //     const blob = try std.mem.dupe(default.allocator, u8, buf[0..read]);
    //     _ = try index.db.database.put(blob);
    // }

    // const tmp: []u8 = try default.allocator.alloc(u8, 10);
    // tmp[0] = 42;
    // const id = try index.db.database.put(tmp);
    // const blob = index.db.database.get(id);
    // std.log.info("id: {any}", .{id});
    // std.log.info("blob: {any}", .{blob});
    // std.log.info("read: {any}", .{index.db.database.store.count()});

    var cwd = std.fs.cwd();
    var dir = try cwd.openDir("test", .{ .iterate = true });
    // var dir = try std.fs.openDirAbsolute("test", .{ .iterate = true });

    var walker = try dir.walk(default.allocator);
    while (try walker.next()) |entry| {
        std.log.err("entry {}", .{entry});
    }
    unreachable;
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
    defer dht.deinit();

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
        try jobs.enqueue(.{ .connect = address });
    }

    std.log.info("Spawning Server Thread..", .{});
    var server_frame = async default.server.start();
    try routing.init_finger_table();

    std.log.info("Server ID: {Server ID}", .{utils.hex(&default.server.id)});

    // start timers
    try timer.start_timer_thread();

    std.log.info("Starting Job loop", .{});

    try jobs.job_loop();
    _ = server_frame;
    unreachable;
}
