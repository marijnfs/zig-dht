pub const io_mode = .evented; // use event loop

const std = @import("std");

usingnamespace @import("index.zig");

fn server_thread_function() !void {
    // default.server = .{ .config = .{ .name = try std.mem.dupe(default.allocator, u8, "127.0.0.1"), .port = 30015 } };

    try default.server.initialize();
    defer default.server.deinit();
    try default.server.accept_loop();

    std.log.info("Accepting frame", .{});
}

pub fn main() !void {
    utils.init_prng();

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
