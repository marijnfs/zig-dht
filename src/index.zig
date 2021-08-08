// Index file that includes the individual classes etc. that are used throughout the software.

pub const Job = @import("job.zig").Job;
pub const connections = @import("connections.zig");
pub const Server = connections.Server;
pub const connect_and_add = connections.connect_and_add;
pub const AtomicQueue = @import("queue.zig").AtomicQueue;
pub const serialise = @import("serialise.zig");
const std = @import("std");

pub const allocator = std.heap.page_allocator;

pub const job = @import("job.zig");
pub const utils = @import("utils.zig");
pub const get_guid = utils.get_guid;
pub const calculate_hash = utils.calculate_hash;

pub const Content = @import("content.zig").Content;

// Common types
const ID_SIZE = 32;
pub const ID = [ID_SIZE]u8;

// Main server instance
pub var server: Server = undefined;
