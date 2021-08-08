// File containing main operations, or 'Jobs'
// They can be scheduled from various places and run in sequence in the main event loop
// These Jobs form the main synchronising organising principle. Jobs can do complex tasks as they are guaranteed to operate alone.

const std = @import("std");
const index = @import("index.zig");
const utils = index.utils;
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
    hash: index.ID,
    data: []u8,
};

const Envelope = struct {
    target: union(enum) {
        guid: u64,
        id: index.ID,
    }, //target output node
    message: Message,
};

pub const Job = union(enum) {
    connect: std.net.Address,
    send_message: Envelope,
    process_message: Message,

    fn work(self: *Job) !void {

        // logger.log_fmt("run job: {}\n", .{self.*});

        switch (self.*) {
            .connect => |address| {
                std.log.info("Connect {s}", .{address});
                try index.connect_and_add(address);
            },
            // Multi function send message,
            // both for incoming and outgoing messages
            .send_message => |envelope| {
                const message = envelope.message;
                switch (envelope.target) {
                    .guid => |guid| {
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
                    .id => |id| {
                        var out_it = index.connections.outgoing_connections.keyIterator();

                        var best_connection: ?*index.connections.OutConnection = null;
                        var lowest_dist = std.mem.zeroes(index.ID);
                        while (out_it.next()) |connection| {
                            if (utils.id_is_zero(connection.*.id))
                                continue;

                            const dist = utils.xor(connection.*.id, index.server.id);
                            if (utils.id_is_zero(lowest_dist) or utils.less(dist, lowest_dist)) {
                                lowest_dist = dist;
                                best_connection = connection.*;
                            }
                        }

                        if (best_connection) |connection| {
                            try connection.*.write(message.data);
                        } else {
                            std.log.info("Couldn't route {any}", .{id});
                        }
                    },
                }
            },
            .process_message => |message| {
                var data_slice = message.data;
                var content = try index.serialise.deserialise(index.Content, &data_slice);
                std.log.info("process message: {any}", .{content});
            },
        }
    }
};
