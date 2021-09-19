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
}, get_known_ips: usize, send_known_ips: []std.net.Address, find: struct { id: ID, inclusive: u8 = 0 }, found: struct { id: ID, address: std.net.Address }, broadcast: []u8 };

pub const Message = struct {
    hash: ID = std.mem.zeroes(ID), //during forward, this is the hash of the message (minus the hash), during backward it is the reply hash
    target_id: ID = std.mem.zeroes(ID),
    source_id: ID = std.mem.zeroes(ID),
    nonce: u64 = 0,
    content: Content,
};

pub const Envelope = struct { target: union(enum) {
    guid: u64,
    id: ID,
}, //target output node
payload: union(enum) {
    raw: []u8,
    message: Message,
} };

pub const InboundMessage = struct {
    guid: u64, //relevant connection guid
    content: []u8,
};

/// >>>>>>>
/// >>>>>>>
pub fn process_forward(source_message: Message, guid: u64) !void {
    const content = source_message.content;

    switch (content) {
        .broadcast => |broadcast| {
            std.log.info("broadcast: '{s}'", .{broadcast});
            try jobs.enqueue(.{ .broadcast = source_message });
        },
        .get_known_ips => |n_ips| {
            // sanity check n_ips

            var addresses = try routing.get_addresses_seen();
            defer default.allocator.free(addresses);

            var selection = try utils.random_selection(n_ips, addresses.len);
            defer default.allocator.free(selection);

            var ips = try default.allocator.alloc(std.net.Address, selection.len);

            var i: usize = 0;
            for (selection) |s| {
                ips[i] = addresses[s];
                i += 1;
            }

            // todo: a message creation function
            //       only needs content,
            //       target_source is often reply, can supply input message, guid
            //       return can directly be a envelope
            const return_content: Content = .{ .send_known_ips = ips };
            const envelope = try build_reply(return_content, source_message, guid);

            try jobs.enqueue(.{ .send_message = envelope });
        },
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
                const envelope = try build_reply(return_content, source_message, guid);
                try jobs.enqueue(.{ .send_message = envelope });
            } else {
                // Pass on message to closest connections
                try jobs.enqueue(.{ .send_message = .{ .target = .{ .guid = best_connection.?.guid }, .payload = .{ .message = source_message } } });
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
            std.log.info("source id seems: {}", .{utils.hex(&source_message.source_id)});

            const return_content: Content = .{ .pong = .{ .apparent_ip = addr } };
            const envelope = try build_reply(return_content, source_message, guid);

            std.log.info("reply env: {any}", .{envelope.payload});

            try jobs.enqueue(.{ .send_message = envelope });
        },
        else => {
            std.log.warn("invalid forward message {any}", .{source_message});
        },
    }
}

/// <<<<<<<
/// <<<<<<<
pub fn process_backward(message: Message, guid: u64) !void {
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
            std.log.info("found result: {s}", .{found});

            const id = found.id;
            const address = found.address;

            try routing.set_finger(id, address);
        },
        .send_known_ips => |known_ips| {
            std.log.info("adding n 'known' addresses: {}", .{known_ips.len});

            defer default.allocator.free(known_ips);
            for (known_ips) |address| {
                try routing.add_address_seen(address);
            }
        },
        else => {
            std.log.warn("invalid forward message {any}", .{message});
        },
    }
}

fn build_reply(content: Content, source_message: Message, guid: u64) !Envelope {
    const reply = Message{ .target_id = source_message.source_id, .source_id = default.server.id, .nonce = utils.get_guid(), .content = content };

    const envelope = Envelope{
        .target = .{ .guid = guid },
        .payload = .{
            .message = reply,
        },
    };
    return envelope;
}
