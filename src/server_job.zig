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
const c = index.c;
const hash = index.hash;
const id_ = index.id;

const ID = index.ID;
const Hash = index.Hash;
const JobQueue = index.JobQueue;

// Jobs
// Main application logic
pub const ServerJob = union(enum) {
    broadcast: communication.Envelope,
    connect: std.net.Address,
    send_message: communication.OutboundMessage,
    inbound_message: communication.InboundMessage,
    process_message: struct {
        guid: u64, //connection guid
        envelope: communication.Envelope,
    },
    callback: fn () anyerror!void,

    pub fn work(self: *ServerJob, queue: *JobQueue(ServerJob)) !void {
        switch (self.*) {
            .process_message => |guid_message| {
                const envelope = guid_message.envelope;
                const guid = guid_message.guid;
                try communication.process_message(envelope, guid);
            },
            // Multi function send message,
            // both for incoming and outgoing messages
            .send_message => |outbound_message| {
                const payload = outbound_message.payload;

                const data = switch (payload) {
                    .raw => |raw_data| raw_data,
                    .envelope => |envelope| blk: {
                        const serial_message = try serial.serialise(envelope);
                        defer default.allocator.free(serial_message);
                        const hash_message = try hash.append_hash(serial_message);
                        std.log.info("send message with hash of: {}", .{utils.hex(&hash_message.hash)});
                        try model.add_hash(hash_message.hash);
                        break :blk hash_message.slice;
                    },
                };
                switch (outbound_message.target) {
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
            .inbound_message => |inbound_message| {
                var data_slice = inbound_message.content;

                var hash_slice = try hash.calculate_and_check_hash(data_slice);

                if (try model.check_and_add_hash(hash_slice.hash)) {
                    std.log.info("message dropped, already seen", .{});
                    return;
                }

                var envelope = try serial.deserialise(communication.Envelope, &hash_slice.slice);

                if (id_.is_zero(envelope.target_id) or id_.is_equal(envelope.target_id, default.server.id)) {
                    std.log.info("message is for me", .{});
                    try queue.enqueue(.{ .process_message = .{ .guid = inbound_message.guid, .envelope = envelope } });
                } else {
                    try queue.enqueue(.{ .send_message = .{ .target = .{ .id = envelope.target_id }, .payload = .{ .raw = data_slice } } });
                }

                std.log.info("process forward message: {any}", .{envelope});
            },
            .broadcast => |broadcast_envelope| {
                std.log.info("broadcasting: {s}", .{broadcast_envelope});
                var it = default.server.outgoing_connections.keyIterator();
                while (it.next()) |conn| {
                    try queue.enqueue(.{ .send_message = .{ .target = .{ .guid = conn.*.guid }, .payload = .{ .envelope = broadcast_envelope } } });
                }

                // Backward routing (might not be a good idea)
                var it_back = default.server.incoming_connections.keyIterator();
                while (it_back.next()) |conn| {
                    try queue.enqueue(.{ .send_message = .{ .target = .{ .guid = conn.*.guid }, .payload = .{ .envelope = broadcast_envelope } } });
                }
            },
            .connect => |address| {
                if (default.server.apparent_address) |apparent_address| {
                    if (std.net.Address.eql(address, apparent_address)) {
                        std.log.info("Asked to connect to our own apparent ip, ignoring", .{});
                        return;
                    }
                }

                std.log.info("Connecting to {s}", .{address});
                const out_connection = try default.server.connect_and_add(address);
                std.log.info("Connected {s}", .{address});
                const content = communication.Content{ .ping = .{ .source_id = default.server.id, .source_port = default.server.config.port } };
                const envelope = communication.Envelope{ .source_id = default.server.id, .nonce = id_.get_guid(), .content = content };
                try queue.enqueue(.{ .send_message = .{ .target = .{ .guid = out_connection.guid }, .payload = .{ .envelope = envelope } } });
            },
            .callback => |callback| {
                try callback();
            },
        }
    }
};
