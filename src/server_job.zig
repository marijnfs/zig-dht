// File containing main operations, or 'ServerJobs'
// They can be scheduled from various places and run in sequence in the main event loop
// These Jobs form the main synchronising organising principle. Jobs can do complex tasks as they are guaranteed to operate alone.

const std = @import("std");
const net = std.net;

const index = @import("index.zig");
const default = index.default;
const communication = index.communication_udp;
const id_ = index.id;
const utils = index.utils;
const serial = index.serial;
const hash = index.hash;
const model = index.model;

const UDPServer = index.UDPServer;

const JobQueue = index.JobQueue(ServerJob, *UDPServer);

pub const ServerJob = union(enum) {
    connect: std.net.Address,
    send_message: communication.OutboundMessage,
    inbound_message: index.socket.UDPIncoming,
    process_message: communication.InboundMessage,
    broadcast: communication.Envelope,
    callback: fn (*UDPServer) anyerror!void,
    stop: bool,

    pub fn work(self: *ServerJob, queue: *JobQueue, server: *UDPServer) !void {
        switch (self.*) {
            .connect => |address| {
                if (server.apparent_address) |apparent_address| {
                    if (std.net.Address.eql(address, apparent_address)) {
                        std.log.info("Asked to connect to our own apparent ip, ignoring", .{});
                        return;
                    }
                }

                // Create ping request
                const content = communication.Content{ .ping = .{ .source_id = server.id, .source_port = server.address.getPort() } };
                const envelope = communication.Envelope{ .source_id = server.id, .nonce = id_.get_guid(), .content = content };
                try queue.enqueue(.{ .send_message = .{ .target = .{ .address = address }, .payload = .{ .envelope = envelope } } });
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
                        const serial_message = try serial.serialise(envelope);
                        defer default.allocator.free(serial_message);
                        const hash_message = try hash.append_hash(serial_message);
                        std.log.info("send message with hash of: {}", .{utils.hex(&hash_message.hash)});
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
                        if (server.id_index.get(id)) |record| {
                            try server.socket.sendTo(record.address, data);
                            return;
                        }

                        // routing
                        if (server.get_closest_record(id)) |record| {
                            try server.socket.sendTo(record.address, data);
                        } else {
                            //failed to find any valid record
                            std.log.info("Failed to find any record for id {}", .{utils.hex(&id)});
                        }
                    },
                }
            },
            .inbound_message => |inbound_message| {
                var data_slice = inbound_message.buf;

                var hash_slice = try hash.calculate_and_check_hash(data_slice);

                if (try model.check_and_add_hash(hash_slice.hash)) {
                    std.log.info("message dropped, already seen", .{});
                    return;
                }

                var envelope = try serial.deserialise(communication.Envelope, &hash_slice.slice);

                if (id_.is_zero(envelope.target_id) or id_.is_equal(envelope.target_id, server.id)) {
                    std.log.info("message is for me", .{});
                    try queue.enqueue(.{ .process_message = .{ .envelope = envelope, .address = inbound_message.from } });
                } else {
                    try queue.enqueue(.{ .send_message = .{ .target = .{ .id = envelope.target_id }, .payload = .{ .raw = data_slice } } });
                }

                std.log.info("process forward message: {any}", .{envelope});
            },
            .broadcast => |broadcast_envelope| {
                std.log.info("broadcasting: {s}", .{broadcast_envelope});
                for (server.records.items) |record| {
                    try queue.enqueue(.{ .send_message = .{ .target = .{ .address = record.address }, .payload = .{ .envelope = broadcast_envelope } } });
                }
            },
            .callback => |callback| {
                try callback(server);
            },
            .stop => |stop| {
                if (stop) {
                    std.log.info("Stop signal for server detecting, stopping job loop", .{});
                    return;
                }
            },
        }
    }
};

test "basics" {
    var job = ServerJob{ .stop = true };
    std.log.info("{}", .{job});
}