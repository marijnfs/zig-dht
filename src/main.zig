pub const io_mode = .evented; // use event loop

const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const timer = index.timer;
const jobs = index.jobs;
const routing = index.routing;
const staging = index.staging;
const readline = index.readline;
const c = index.c;

pub const log_level: std.log.Level = .warn;

fn server_thread_function() !void {
    try default.server.initialize();
    defer default.server.deinit();
    try default.server.accept_loop();

    std.log.info("Server Ended", .{});
}

pub fn time_test() void {
    std.log.info("timer", .{});
}

pub fn main() !void {
    try index.init();
    defer index.deinit();

    try timer.add_timer(10000, staging.expand_connections, true);
    try timer.add_timer(20000, staging.refresh_finger_table, true);
    try timer.add_timer(30000, staging.sync_finger_table, true);
    try timer.add_timer(30000, staging.clear_closed_connections, true);
    try timer.add_timer(60000, staging.detect_self_connection, true);

    var args = try std.process.argsAlloc(default.allocator);
    defer std.process.argsFree(default.allocator, args);
    std.log.info("arg0 {s}", .{args[0]});

    if (args.len < 4) {
        std.log.err("Usage: {s} [username] [localip] [localport] ([remote ip] [remote port])*", .{args[0]});
        return error.MissingUsername;
    }

    {
        const port = try std.fmt.parseInt(u16, args[3], 0);
        default.server.config = .{ .name = args[2], .port = port };
        const username = args[1];
        default.server.config.username = try std.mem.dupe(default.allocator, u8, username);
        std.log.info("Username: {s}", .{default.server.config.username});
    }

    if (args.len >= 5) {
        const port = try std.fmt.parseInt(u16, args[5], 0);
        const addr = try std.net.Address.parseIp(args[4], port);
        try routing.add_address_seen(addr);
        try jobs.enqueue(.{ .connect = addr });
    }

    std.log.info("Spawning Server Thread..", .{});
    var server_frame = async server_thread_function();
    try routing.init_finger_table();

    std.log.info("Server ID: {Server ID}", .{utils.hex(&default.server.id)});

    // start timers
    try timer.start_timer_thread();

    // start readline
    try readline.start_readline_thread();

    std.log.info("Starting Job loop", .{});

    try jobs.job_loop();
    _ = server_frame;
    unreachable;
    // try await server_frame;
}

test "job" {
    // var job = index.Job{ .connect = "sdf" };
}
