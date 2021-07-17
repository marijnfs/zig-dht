pub const io_mode = .evented; // use event loop

const std = @import("std");

const index = @import("index.zig");

var server: index.Server = undefined;
// var server_thread: std.Thread = undefined;

fn server_thread_function() !void {
    server = index.Server{ .config = .{ .name = try std.mem.dupe(index.allocator, u8, "127.0.0.1"), .port = 30011 } };

    try server.initialize();

    try server.accept_loop();

    std.log.info("Accepting frame", .{});
}

pub fn main() !void {
    std.log.info("Spawning Server Thread..", .{});

    var server_frame = async server_thread_function();

    std.log.info("Starting loop", .{});
    index.job.job_loop();
    std.log.info("Done", .{});
    try await server_frame;
}

test "job" {
    // var job = index.Job{ .connect = "sdf" };
}
