// Index file that includes the individual classes etc. that are used throughout the software.

const std = @import("std");
const time = std.time;

pub const server_job = @import("server_job.zig");
pub const job_queue = @import("job_queue.zig");
pub const connections = @import("connections.zig");
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
pub const server = @import("server.zig");
pub const bot = @import("bot.zig");

// Quick Definitions
pub const Server = server.Server;
pub const ID = id.ID;
pub const Hash = id.Hash;
pub const JobQueue = job_queue.JobQueue;
pub const AtomicQueue = @import("queue.zig").AtomicQueue;
pub const ServerJob = server_job.ServerJob;

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub var rng = std.rand.DefaultPrng.init(0);

pub const default = struct {
    pub const allocator = gpa.allocator();

    // Main server instance
    pub var server: *Server = undefined;
    pub const target_connections = 8;
    pub const n_fingers = 8;
};

pub fn init() !void {
    std.log.info("index.init", .{});

    try seed_rng();
    id.init();
    model.init();
}

pub fn seed_rng() !void {
    // const seed = std.crypto.random.int(u64);
    const seed = @intCast(u64, time.milliTimestamp());
    rng = std.rand.DefaultPrng.init(seed);
}

test "rng" {
    const random = std.crypto.random;
    const seed = random.int(u64);
    std.log.info("{}", .{seed});
}
