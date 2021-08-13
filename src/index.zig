// Index file that includes the individual classes etc. that are used throughout the software.

pub const jobs = @import("jobs.zig");
pub const connections = @import("connections.zig");
pub const AtomicQueue = @import("queue.zig").AtomicQueue;
pub const serialise = @import("serialise.zig");
pub const utils = @import("utils.zig");

const std = @import("std");

pub const default = struct {
    pub const allocator = std.heap.page_allocator;

    // Main server instance
    pub var server: @import("server.zig").Server = undefined;
};

pub const get_guid = utils.get_guid;

pub const Data = @import("data.zig").Data;

// Common types
const ID_SIZE = 32;
pub const ID = [ID_SIZE]u8;
