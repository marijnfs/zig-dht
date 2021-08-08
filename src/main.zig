pub const io_mode = .evented; // use event loop

const std = @import("std");

const index = @import("index.zig");

fn server_thread_function() !void {
    index.server = index.Server{ .config = .{ .name = try std.mem.dupe(index.allocator, u8, "127.0.0.1"), .port = 30015 } };

    try index.server.initialize();
    defer index.server.deinit();
    try index.server.accept_loop();

    std.log.info("Accepting frame", .{});
}

pub fn main() !void {
    std.log.info("Spawning Server Thread..", .{});

    var server_frame = async server_thread_function();

    std.log.info("Starting Job loop", .{});
    index.job.job_loop();
    std.log.info("Done", .{});

    try await server_frame;
}

test "job" {
    // var job = index.Job{ .connect = "sdf" };
}
