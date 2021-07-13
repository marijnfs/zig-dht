// Index file that includes the individual classes etc. that are used throughout the software.

pub const Job = @import("job.zig").Job;
pub const Server = @import("connections.zig").Server;

const std = @import("std");

pub const allocator = std.heap.page_allocator;
