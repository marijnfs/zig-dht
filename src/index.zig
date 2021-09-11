// Index file that includes the individual classes etc. that are used throughout the software.

pub const jobs = @import("jobs.zig");
pub const connections = @import("connections.zig");
pub const AtomicQueue = @import("queue.zig").AtomicQueue;
pub const serial = @import("serial.zig");
pub const utils = @import("utils.zig");
pub const routing = @import("routing.zig");
pub const communication = @import("communication.zig");
pub const model = @import("model.zig");
pub const staging = @import("staging.zig");
pub const timer = @import("timer.zig");

const std = @import("std");

pub const default = struct {
    pub const allocator = std.heap.page_allocator;

    // Main server instance
    pub var server: @import("server.zig").Server = undefined;

    pub const target_connections = 8;
};

pub fn init() void {
    utils.init_prng();
    
}

// Common types
const ID_SIZE = 32;
pub const ID = [ID_SIZE]u8;
pub const Hash = [ID_SIZE]u8;
