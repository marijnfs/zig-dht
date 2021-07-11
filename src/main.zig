const std = @import("std");

const index = @import("index.zig");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}

test "job" {
    var job = index.Job{ .connect = "sdf" };
}
