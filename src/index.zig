// Index file that includes the individual classes etc. that are used throughout the software.

const std = @import("std");

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
pub const timer_functions = @import("timer_functions.zig");
pub const db = @import("db.zig");
pub const hash = @import("hash.zig");
pub const id = @import("id.zig");
pub const c = @import("c.zig");
pub const server = @import("server.zig");

// Quick Definitions
pub const Server = server.Server;
pub const ID = id.ID;
pub const Hash = id.Hash;

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub var rng = std.rand.DefaultPrng.init(0);

pub const default = struct {
    pub const allocator = gpa.allocator();

    // Main server instance
    pub var server: *Server = undefined;
    pub const target_connections = 8;
};

pub fn init() !void {
    std.log.info("index.init", .{});

    try seed_rng();
    id.init();
    model.init();
    jobs.init();
    // try c.init();
}

pub fn deinit() void {
    c.deinit();
}

fn seed_rng() !void {
    rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp()));
}
