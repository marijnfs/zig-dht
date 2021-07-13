pub const io_mode = .evented; // use event loop

const std = @import("std");

const index = @import("index.zig");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});

    var server = index.Server{ .config = .{ .name = try std.mem.dupe(index.allocator, u8, "127.0.0.1"), .port = 30011 } };

    try server.initialize();

    var accept_frame = async server.accept_loop();
    std.log.info("Accepting frame", .{});
    // while (true) {
    try await accept_frame;
    // }
    std.log.info("Done", .{});
}

test "job" {
    var job = index.Job{ .connect = "sdf" };
}
