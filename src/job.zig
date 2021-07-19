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

const Message = struct {
    guid: u64,
    data: []u8,
};

pub const Job = union(enum) {
    connect: std.net.Address,
    send_message: Message,
    process_message: Message,

    fn work(self: *Job) !void {

        // logger.log_fmt("run job: {}\n", .{self.*});

        switch (self.*) {
            .connect => |address| {
                std.log.info("Connect {s}", .{address});
                try index.connect_and_add(address);
            },
            .send_message => |message| {
                const guid = message.guid;
                // first find the ingoing or outgoing connection
                var in_it = index.connections.incoming_connections.keyIterator();
                while (in_it.next()) |connection| {
                    if (connection.*.guid == guid) {
                        try connection.*.write(message.data);
                        break;
                    }
                }

                var out_it = index.connections.outgoing_connections.keyIterator();
                while (out_it.next()) |connection| {
                    if (connection.*.guid == guid) {
                        try connection.*.write(message.data);
                        break;
                    }
                }

                std.log.info("Wrote message {s}", .{message});
            },
            .process_message => |message| {
                if (index.connections.route_guid(message.guid)) |connection_guid| {
                    try enqueue(.{ .send_message = .{ .guid = connection_guid, .data = message.data } });
                } else {
                    std.log.info("Failed to process message", .{});
                }
            },
        }
    }
};
