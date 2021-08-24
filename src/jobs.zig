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
pub const Job = union(enum) {
    connect: std.net.Address,
    send_message: communication.Envelope,
    inbound_forward_message: communication.InboundMessage,
    inbound_backward_message: communication.InboundMessage,
    process_forward: struct {
        guid: u64,
        message: communication.Message,
    },
    process_backward: struct {
        guid: u64,
        message: communication.Message,
    },

    fn work(self: *Job) !void {
        switch (self.*) {
            .process_forward => |guid_message| {
                const message = guid_message.message;
                const guid = guid_message.guid;
                try communication.process_forward(message, guid);
                //this means the message is for us
                //most of the main domain code is here
            },
            .process_backward => |guid_message| {
                const message = guid_message.message;
                const guid = guid_message.guid;
                try communication.process_backward(message, guid);
                //this means the message is for us
                //most of the main domain code is here
            },

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
                    .message => |message| blk: {
                        std.log.info("test message: {}", .{message});
                        var slice = try serial.serialise(message);
                        //calculate the hash
                        const hash = utils.calculate_hash(slice[@sizeOf(Hash)..]);
                        std.mem.copy(u8, slice[0..@sizeOf(Hash)], &hash);
                        std.log.info("serialized len before sending: {}", .{slice.len});
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

                        std.log.info("Wrote message {} {s}", .{ data.len, data });
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
            .inbound_forward_message => |inbound_message| {
                var data_slice = inbound_message.content;

                var hash_slice = try calculate_and_check_hash(data_slice);

                if ((try model.hashes_seen.getOrPut(hash_slice.hash)).found_existing) {
                    std.log.info("message dropped, already seen", .{});
                    return;
                }

                var message = try serial.deserialise(communication.Message, &hash_slice.slice);

                if (utils.id_is_zero(message.target_id) or utils.id_is_equal(message.target_id, default.server.id)) {
                    std.log.info("message is for me", .{});
                    try jobs.enqueue(.{ .process_forward = .{ .guid = inbound_message.guid, .message = message } });
                } else {
                    try jobs.enqueue(.{ .send_message = .{ .target = .{ .id = message.target_id }, .payload = .{ .raw = data_slice } } });
                }

                std.log.info("process forward message: {any}", .{message});
            },
            .inbound_backward_message => |inbound_message| {
                var data_slice = inbound_message.content;
                // const hash = message.hash;

                var hash_slice = try calculate_and_check_hash(data_slice);
                data_slice = hash_slice.slice;
                const message = try serial.deserialise(communication.Message, &data_slice);

                std.log.info("process backward message: {any}", .{inbound_message});

                if (utils.id_is_equal(message.target_id, default.server.id)) {
                    try jobs.enqueue(.{ .process_backward = .{ .guid = inbound_message.guid, .message = message } });
                } else {
                    try jobs.enqueue(.{ .send_message = .{ .target = .{ .id = message.target_id }, .payload = .{ .raw = data_slice } } });
                }
            },
        }
    }
};

const RetType = struct { hash: Hash, slice: []u8 };
fn calculate_and_check_hash(data_slice: []u8) !RetType {
    if (data_slice.len < @sizeOf(Hash)) {
        std.log.info("message dropped", .{});
        return error.TooShort;
    }

    const reported_hash: Hash = data_slice[0..@sizeOf(Hash)].*;

    const calculated_hash = utils.calculate_hash(data_slice[@sizeOf(Hash)..]);
    if (!utils.id_is_equal(reported_hash, calculated_hash)) {
        std.log.info("message dropped, hash doesn't match", .{});
        return error.FalseHash;
    }
    return RetType{ .hash = calculated_hash, .slice = data_slice[@sizeOf(Hash)..] };
}
