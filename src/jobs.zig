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

const Envelope = struct { target: union(enum) {
    guid: u64,
    id: ID,
}, //target output node
payload: union(enum) {
    raw: []u8,
    message: communication.Message,
} };

pub const InboundMessage = struct {
    guid: u64,
    content: []u8,
};

pub const Job = union(enum) {
    connect: std.net.Address,
    send_message: Envelope,
    forward_message: InboundMessage,
    backward_message: InboundMessage,

    fn work(self: *Job) !void {
        switch (self.*) {
            .connect => |address| {
                std.log.info("Connect {s}, sending ping: {any}", .{ address, default.server.id });
                const out_connection = try default.server.connect_and_add(address);
                const content = communication.Content{ .ping = .{ .source_id = default.server.id } };
                const message = communication.Message{ .content = content };
                try enqueue(.{ .send_message = .{ .target = .{ .guid = out_connection.guid }, .payload = .{ .message = message } } });
            },
            // Multi function send message,
            // both for incoming and outgoing messages
            .send_message => |envelope| {
                const payload = envelope.payload;

                const data = switch (payload) {
                    .raw => |raw_data| raw_data,
                    else => blk: {
                        var buf = std.ArrayList(u8).init(default.allocator);
                        try serialise.serialise_to_buffer(payload, &buf);
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
            .forward_message => |inbound_message| {
                var data_slice = inbound_message.content;
                if (data_slice.len < @sizeOf(ID)) {
                    std.log.info("message dropped", .{});
                    return;
                }

                const reported_hash: ID = data_slice[0..@sizeOf(ID)].*;
                if ((try model.hashes_seen.getOrPut(reported_hash)).found_existing) {
                    std.log.info("message dropped, already seed", .{});
                    return;
                }

                const calculated_hash = utils.calculate_hash(data_slice[@sizeOf(ID)..]);
                if (!utils.id_is_equal(reported_hash, calculated_hash)) {
                    std.log.info("message dropped, hash doesn't match", .{});
                    return;
                }

                var message = try serialise.deserialise(communication.Message, &data_slice);

                if (utils.id_is_zero(message.target_id) or utils.id_is_equal(message.target_id, default.server.id)) {
                    std.log.info("message is for me", .{});
                }
                std.log.info("process forward message: {any}", .{message});
            },
            .backward_message => |message| {
                var data_slice = message.content;
                // const hash = message.hash;

                var content = try serialise.deserialise(communication.Content, &data_slice);
                std.log.info("process backward message: {any}", .{content});
            },
        }
    }
};
