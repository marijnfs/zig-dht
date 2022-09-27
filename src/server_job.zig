// File containing main operations, or 'ServerJobs'
// They can be scheduled from various places and run in sequence in the main event loop
// These Jobs form the main synchronising organising principle. Jobs can do complex tasks as they are guaranteed to operate alone.

const std = @import("std");
const net = std.net;

const index = @import("index.zig");
const default = index.default;
const communication = index.communication;
const id_ = index.id;
const utils = index.utils;
const serial = index.serial;
const hash = index.hash;
const model = index.model;
const hex = index.hex;

const Server = index.Server;

const JobQueue = index.JobQueue(ServerJob, *Server);

pub const ServerJob = union(enum) {
    connect: struct {
        address: std.net.Address,
        public: bool,
    },
    send_message: communication.OutboundMessage,
    inbound_message: index.socket.UDPIncoming,
    process_message: communication.InboundMessage,
    broadcast: communication.Envelope,
    callback: fn (*Server) anyerror!void,
    stop: bool,

    pub fn work(self: *ServerJob, queue: *JobQueue, server: *Server) !void {
        switch (self.*) {
            .connect => |connect| {
                if (server.apparent_address) |apparent_address| {
                    if (std.net.Address.eql(connect.address, apparent_address)) {
                        std.log.debug("Asked to connect to our own apparent ip, ignoring", .{});
                        return;
                    }
                }

                if (connect.public) {
                    // Create ping request
                    try communication.enqueue_envelope(.{ .ping = .{ .public = server.public } }, .{ .address = connect.address }, server);
                } else {
                    if (server.public_finger_table.get_closest_active_finger(server.id)) |finger| //todo, doesn't need to be closest to me, this was just convenient. Random is maybe better
                    {
                        try communication.enqueue_envelope(.{ .punch_suggest = .{ .suggested_public_address = finger.address, .nonce = id_.rand_id() } }, .{ .address = connect.address }, server);
                    } else {
                        std.log.debug("Don't have any public fingers, can't connect to private", .{});
                    }
                }
            },
            .process_message => |inbound| {
                try communication.process_message(inbound.envelope, inbound.address, server);
            },
            // Multi function send message,
            // both for incoming and outgoing messages
            .send_message => |outbound_message| {
                const payload = outbound_message.payload;

                const data = switch (payload) {
                    .raw => |raw_data| raw_data,
                    .envelope => |envelope| b: {
                        const serial_message = try serial.serialise_alloc(envelope, default.allocator);
                        defer default.allocator.free(serial_message);
                        const hash_message = try hash.append_hash(serial_message);
                        std.log.debug("send message with hash of: {}", .{hex(&hash_message.hash)});

                        try model.add_hash(hash_message.hash);

                        break :b hash_message.slice;
                    },
                };
                switch (outbound_message.target) {
                    .address => |address| {
                        try server.socket.sendTo(address, data);
                    },
                    .id => |id| {
                        //direct match
                        if (server.routing.id_index.get(id)) |record| {
                            try server.socket.sendTo(record.address, data);
                            return;
                        }

                        //backroute match
                        if (server.routing.get_backroute(id)) |addr| {
                            try server.socket.sendTo(addr, data);
                            return;
                        }

                        // routing
                        var finger_table = b: {
                            if (outbound_message.public) {
                                break :b server.public_finger_table;
                            } else {
                                break :b server.finger_table;
                            }
                        };

                        if (id_.is_zero(id)) { //pick a random target
                            if (try finger_table.get_random_active_finger()) |finger| {
                                try server.socket.sendTo(finger.address, data);
                            } else {
                                std.log.debug("Failed to find any random active connection", .{});
                            }
                            return;
                        }

                        if (finger_table.get_closest_active_finger(id)) |finger| {
                            try server.socket.sendTo(finger.address, data);
                        } else {
                            //failed to find any valid record
                            std.log.debug("Failed to find any finger for id {}", .{hex(&id)});
                        }
                    },
                }
            },
            .inbound_message => |inbound_message| {
                var data_slice = inbound_message.buf;

                var hash_slice = try hash.calculate_and_check_hash(data_slice);
                if (try model.check_and_add_hash(hash_slice.hash)) {
                    std.log.debug("message dropped, already seen", .{});
                    return;
                }

                var reader = std.io.fixedBufferStream(hash_slice.slice).reader();
                var envelope = try serial.deserialise(communication.Envelope, reader, default.allocator);

                // back routing
                try server.routing.add_backroute(envelope.source_id, inbound_message.from);

                std.log.debug("got msg:{}", .{envelope.content});

                if (id_.is_zero(envelope.target_id) or id_.is_equal(envelope.target_id, server.id)) {
                    std.log.debug("message is for me", .{});
                    try queue.enqueue(.{ .process_message = .{ .envelope = envelope, .address = inbound_message.from } });
                } else {
                    try queue.enqueue(.{ .send_message = .{ .target = .{ .id = envelope.target_id }, .payload = .{ .raw = data_slice } } });
                }

                std.log.debug("process forward message: {any}", .{envelope});
            },
            .broadcast => |broadcast_envelope| {
                std.log.debug("broadcasting: {s}", .{broadcast_envelope});
                {
                    var it = server.finger_table.valueIterator();
                    while (it.next()) |finger| {
                        if (finger.is_zero())
                            continue;
                        std.log.debug("broadcast to finger: {s}", .{finger.address});

                        try queue.enqueue(.{ .send_message = .{ .target = .{ .address = finger.address }, .payload = .{ .envelope = broadcast_envelope } } });
                    }
                }
                {
                    var it = server.public_finger_table.valueIterator();
                    while (it.next()) |finger| {
                        if (finger.is_zero())
                            continue;
                        std.log.debug("broadcast to finger: {s}", .{finger.address});

                        try queue.enqueue(.{ .send_message = .{ .target = .{ .address = finger.address }, .payload = .{ .envelope = broadcast_envelope } } });
                    }
                }
            },
            .callback => |callback| {
                try callback(server);
            },
            .stop => |stop| {
                if (stop) {
                    std.log.debug("Stop signal for server detecting, stopping job loop", .{});
                    return;
                }
            },
        }
    }
};

test "basics" {
    var job = ServerJob{ .stop = true };
    std.log.debug("{}", .{job});
}
