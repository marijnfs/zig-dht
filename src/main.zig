pub const io_mode = .evented; // use event loop

const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const timer = index.timer;
const jobs = index.jobs;
const staging = index.staging;

fn server_thread_function() !void {
    // default.server = .{ .config = .{ .name = try std.mem.dupe(default.allocator, u8, "127.0.0.1"), .port = 30015 } };

    try default.server.initialize();
    defer default.server.deinit();
    try default.server.accept_loop();

    std.log.info("Accepting frame", .{});
}

pub fn time_test() void {
    std.log.info("timer", .{});
}
pub fn main() !void {
    utils.init_prng();

    try timer.add_timer(1000, staging.expand_connections, false);
    try timer.add_timer(2000, staging.refresh_finger_table, false);
    try timer.add_timer(3000, staging.sync_finger_table, false);

    try timer.start_timer_thread();

    var args = try std.process.argsAlloc(default.allocator);
    defer std.process.argsFree(default.allocator, args);

    std.log.info("args: {s}", .{args[1]});

    if (args.len > 1) {
        const port = try std.fmt.parseInt(u16, args[2], 0);
        default.server.config = .{ .name = args[1], .port = port };
    }
    if (args.len > 3) {
        const port = try std.fmt.parseInt(u16, args[4], 0);
        const addr = try std.net.Address.parseIp(args[3], port);
        try jobs.enqueue(.{ .connect = addr });
    }

    std.log.info("Spawning Server Thread..", .{});
    var server_frame = async server_thread_function();

    std.log.info("Starting Job loop", .{});
    jobs.job_loop();
    std.log.info("Done", .{});
    try await server_frame;
}

test "job" {
    // var job = index.Job{ .connect = "sdf" };
}
