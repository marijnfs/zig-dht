// File containing main operations, or 'Jobs'
// They can be scheduled from various places and run in sequence in the main event loop
// These Jobs form the main synchronising organising principle. Jobs can do complex tasks as they are guaranteed to operate alone.

const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const communication = index.communication;
const serial = index.serial;
const utils = index.utils;
const connections = index.connections;
const model = index.model;
const jobs = index.jobs;

const AtomicQueue = index.AtomicQueue;
const ID = index.ID;
const Hash = index.Hash;

pub var job_queue = AtomicQueue(Job).init(default.allocator);

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
                std.log.info("Connect {s}, sending ping: {}", .{ address, utils.hex(&default.server.id) });
                const out_connection = try default.server.connect_and_add(address);
                const content = communication.Content{ .ping = .{ .source_id = default.server.id, .source_port = default.server.config.port } };
                const message = communication.Message{ .source_id = default.server.id, .content = content };
                try enqueue(.{ .send_message = .{ .target = .{ .guid = out_connection.guid }, .payload = .{ .message = message } } });
            },
            // Multi function send message,
            // both for incoming and outgoing messages
            .send_message => |envelope| {
                const payload = envelope.payload;

                const data = switch (payload) {
                    .raw => |raw_data| raw_data,
                    .message => |message| blk: {
                        const serial_message = try serial.serialise(message);
                        const hash = utils.calculate_hash(serial_message);

                        const hash_message = try default.allocator.alloc(u8, hash.len + serial_message.len);
                        std.mem.copy(u8, hash_message[0..hash.len], &hash);
                        std.mem.copy(u8, hash_message[hash.len..], serial_message);
                        std.log.info("send message with hash of : {}", .{hash_message.len});

                        break :blk hash_message;
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

                        std.log.info("Wrote message {} {any}", .{ data.len, data });
                    },
                    .id => |id| {
                        var best_connection = default.server.get_closest_outgoing_connection(id);

                        if (best_connection) |connection| {
                            try connection.*.write(data);
                        } else {
                            std.log.info("Couldn't route {}", .{utils.hex(&id)});
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
                    std.log.info("for me, target_id: {}", .{utils.hex(&message.target_id)});

                    try jobs.enqueue(.{ .process_backward = .{ .guid = inbound_message.guid, .message = message } });
                } else {
                    std.log.info("pass on, target_id: {}", .{utils.hex(&message.target_id)});
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
    const body_slice = data_slice[@sizeOf(Hash)..];
    const calculated_hash = utils.calculate_hash(body_slice);
    if (!utils.id_is_equal(reported_hash, calculated_hash)) {
        std.log.info("message dropped, hash doesn't match", .{});
        return error.FalseHash;
    }
    return RetType{ .hash = calculated_hash, .slice = body_slice };
}
