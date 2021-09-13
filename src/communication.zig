const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;
const communication = index.communication;
const routing = index.routing;
const utils = index.utils;

const ID = index.ID;

// Message contents
pub const Content = union(enum) { ping: struct { source_id: ID, source_port: u16 }, pong: struct {
    apparent_ip: std.net.Address,
}, get_known_ips: usize, send_known_ips: []std.net.Address, find: struct { id: ID, inclusive: u8 = 0 }, found: struct { id: ID, address: std.net.Address } };

pub const Message = struct {
    hash: ID = std.mem.zeroes(ID), //during forward, this is the hash of the message (minus the hash), during backward it is the reply hash
    target_id: ID = std.mem.zeroes(ID),
    source_id: ID = std.mem.zeroes(ID),
    content: Content,
};

pub const Envelope = struct { target: union(enum) {
    guid: u64,
    id: ID,
}, //target output node
payload: union(enum) {
    raw: []u8,
    message: communication.Message,
} };

pub const InboundMessage = struct {
    guid: u64, //relevant connection guid
    content: []u8,
};

/// >>>>>>>
/// >>>>>>>
pub fn process_forward(message: communication.Message, guid: u64) !void {
    const content = message.content;

    switch (content) {
        .find => |find| {
            // requester is trying to find a node closest to the search_id
            // We want to figure out if that's us (to our knowledge); if not we pass on the search

            std.log.info("finding: {}", .{find});

            const search_id = find.id;
            var best_connection = default.server.get_closest_outgoing_connection(search_id);

            var we_are_closest: bool = false;
            if (best_connection) |connection| {
                // check if the closest connection is closer than us

                const conn_dist = utils.xor(connection.*.id, search_id);
                const our_dist = utils.xor(default.server.id, search_id);

                we_are_closest = utils.less(our_dist, conn_dist);
            } else {
                //We don't have connections apparently, so we assume we are the closest
                we_are_closest = true;
            }

            if (we_are_closest) {
                // Return message
                const return_content: Content = .{ .found = .{ .id = default.server.id, .address = default.server.apparent_address } };
                const return_message = communication.Message{ .target_id = message.source_id, .source_id = default.server.id, .content = return_content };

                const envelope = communication.Envelope{
                    .target = .{ .guid = guid },
                    .payload = .{
                        .message = return_message,
                    },
                };
                try jobs.enqueue(.{ .send_message = envelope });
            } else {
                // Pass on message to closest connections
                try jobs.enqueue(.{ .send_message = .{ .target = .{ .guid = best_connection.?.guid }, .payload = .{ .message = message } } });
            }
        },
        .ping => |ping| {
            std.log.info("got ping: {}", .{ping});

            // Resolve the possible connection address
            const conn = try default.server.get_incoming_connection(guid);
            var addr = conn.address();
            addr.setPort(ping.source_port);
            try routing.add_address_seen(addr);

            std.log.info("got ping from addr: {any}", .{addr});
            std.log.info("source id seems: {}", .{utils.hex(&message.source_id)});

            const return_content: Content = .{ .pong = .{ .apparent_ip = addr } };
            const return_message = communication.Message{ .target_id = message.source_id, .source_id = default.server.id, .content = return_content };

            const envelope = communication.Envelope{
                .target = .{ .guid = guid },
                .payload = .{
                    .message = return_message,
                },
            };
            std.log.info("reply env: {any}", .{envelope.payload});

            try jobs.enqueue(.{ .send_message = envelope });
        },
        else => {
            std.log.warn("invalid forward message {any}", .{message});
        },
    }
}

/// <<<<<<<
/// <<<<<<<
pub fn process_backward(message: communication.Message, guid: u64) !void {
    const content = message.content;

    switch (content) {
        .pong => |pong| {
            std.log.info("got pong: {}", .{pong});
            const conn = try default.server.get_outgoing_connection(guid);
            const addr = conn.address;
            conn.id = message.source_id;

            var our_ip = pong.apparent_ip;
            our_ip.setPort(default.server.config.port); // set the port so the address becomes our likely external connection ip
            default.server.apparent_address = our_ip;
            std.log.info("setting source id, for {s}: {any} {s}", .{ addr, conn.id, our_ip });
        },
        .found => |found| {
            std.log.info("found result: {}", .{found});
            @panic("got a found");
        },
        else => {
            std.log.warn("invalid forward message {any}", .{message});
        },
    }
}
