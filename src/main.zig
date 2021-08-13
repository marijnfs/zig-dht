pub const io_mode = .evented; // use event loop

const std = @import("std");

usingnamespace @import("index.zig");

fn server_thread_function() !void {
    default.server = .{ .config = .{ .name = try std.mem.dupe(default.allocator, u8, "127.0.0.1"), .port = 30015 } };

    try default.server.initialize();
    defer default.server.deinit();
    try default.server.accept_loop();

    std.log.info("Accepting frame", .{});
}

pub fn main() !void {
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
