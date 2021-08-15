// File containing main operations, or 'Jobs'
// They can be scheduled from various places and run in sequence in the main event loop
// These Jobs form the main synchronising organising principle. Jobs can do complex tasks as they are guaranteed to operate alone.

const std = @import("std");
usingnamespace @import("index.zig");
var job_queue = AtomicQueue(Job).init(default.allocator);

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
    hash: ID,
    content: []u8,
};

const Envelope = struct {
    target: union(enum) {
        guid: u64,
        id: ID,
    }, //target output node
    content: communication.Data,
};

pub const Job = union(enum) {
    connect: std.net.Address,
    send_message: Envelope,
    process_message: Message,

    fn work(self: *Job) !void {
        switch (self.*) {
            .connect => |address| {
                std.log.info("Connect {s}", .{address});
                const out_connection = try default.server.connect_and_add(address);
                try enqueue(.{ .send_message = .{ .target = .{ .guid = out_connection.guid }, .content = .{ .ping = .{ .source_id = default.server.id } } } });
            },
            // Multi function send message,
            // both for incoming and outgoing messages
            .send_message => |envelope| {
                const content = envelope.content;

                const data = switch (content) {
                    .raw => |raw_data| raw_data,
                    else => blk: {
                        var buf = std.ArrayList(u8).init(default.allocator);
                        try serialise.serialise_to_buffer(content, &buf);
                        const slice = buf.toOwnedSlice();
                        break :blk slice;
                    },
                };
                switch (envelope.target) {
                    .guid => |guid| {
                        // first find the ingoing or outgoing connection
                        var in_it = default.server.incoming_connections.keyIterator();
                        while (in_it.next()) |connection| {
                            if (connection.*.guid == guid) {
                                try connection.*.write(data);
                                break;
                            }
                        }

                        var out_it = default.server.outgoing_connections.keyIterator();
                        while (out_it.next()) |connection| {
                            if (connection.*.guid == guid) {
                                try connection.*.write(data);
                                break;
                            }
                        }

                        std.log.info("Wrote message {s}", .{data});
                    },
                    .id => |id| {
                        var out_it = default.server.outgoing_connections.keyIterator();

                        var best_connection: ?*connections.OutConnection = null;
                        var lowest_dist = std.mem.zeroes(ID);
                        while (out_it.next()) |connection| {
                            if (utils.id_is_zero(connection.*.id))
                                continue;

                            const dist = utils.xor(connection.*.id, default.server.id);
                            if (utils.id_is_zero(lowest_dist) or utils.less(dist, lowest_dist)) {
                                lowest_dist = dist;
                                best_connection = connection.*;
                            }
                        }

                        if (best_connection) |connection| {
                            try connection.*.write(data);
                        } else {
                            std.log.info("Couldn't route {any}", .{id});
                        }
                    },
                }
            },
            .process_message => |message| {
                var data_slice = message.content;
                var content = try serialise.deserialise(communication.Data, &data_slice);
                std.log.info("process message: {any}", .{content});
            },
        }
    }
};
