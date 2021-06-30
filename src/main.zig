const std = @import("std");

const job = @import("job");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}

test "job" {}
