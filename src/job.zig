// File containing main operations, or 'Jobs'
// They can be scheduled from various places and run in sequence in the main event loop
// These Jobs form the main synchronising organising principle. Jobs can do complex tasks as they are guaranteed to operate alone.

const std = @import("std");
const index = @import("index.zig");
var job_queue = index.AtomicQueue(Job).init(index.allocator);

pub fn enqueue(job: Job) !void {
    // logger.log_fmt("queuing job: {}\n", .{job});
    try job_queue.push(job);
}

pub fn job_loop() void {
    while (true) {
        if (job_queue.pop()) |*job| {
            job.work() catch |e| {
                std.log.info("Work Error: {}", .{e});
            };
        } else {
            //sleep
            std.os.nanosleep(0, 1000000);
        }
    }
}

// Jobs
// Main application logic
const Address = []u8;

const SendMessage = struct {
    guid: u64,
    message: []u8,
};

pub const Job = union(enum) {
    connect: Address,
    message: SendMessage,

    fn work(self: *Job) !void {

        // logger.log_fmt("run job: {}\n", .{self.*});

        switch (self.*) {
            .connect => |address| {
                std.log.info("Connect {s}", .{address});
            },
            .message => |message| {
                std.log.info("Got message {s}", .{message});
            },
        }
    }
};
