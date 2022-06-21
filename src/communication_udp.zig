const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const routing = index.routing;
const utils = index.utils;
const c = index.c;
const id_ = index.id;
const ID = index.ID;
const udp_server = index.udp_server;
// Message contents

pub const Content = union(enum) {
    ping: struct {
        // source_port: u16,
        bla: u64 = 0, //void mights till be broken
    },
    pong: struct {
        apparent_ip: std.net.Address,
    },
    get_known_ips: usize,
    send_known_ips: []std.net.Address,
    find: struct {
        id: ID,
        inclusive: u8 = 0,
    },
    found: struct {
        id: ID,
        address: ?std.net.Address,
    },
    punch_suggest: struct {
        nonce: ID, //nonce for coordination
        suggested_public_address: std.net.Address,
    },
    punch_accept: struct {
        nonce: ID, //nonce for coordination
        suggested_public_address: std.net.Address,
    },

    punch_request: struct {
        nonce: ID, //nonce for coordination
        initiator: bool,
    },
    punch_reply: struct {
        nonce: ID,
        punch_address: std.net.Address,
    },
    broadcast: []const u8,
    direct_message: []const u8,
};

pub const Envelope = struct {
    hash: ID = std.mem.zeroes(ID), //during forward, this is the hash of the message (minus the hash), during backward it is the reply hash
    target_id: ID = std.mem.zeroes(ID),
    source_id: ID = std.mem.zeroes(ID),
    nonce: u64 = 0,
    content: Content,
};

const Target = union(enum) {
    id: ID,
    address: std.net.Address,
};

pub const OutboundMessage = struct {
    target: Target, //target output node
    payload: union(enum) {
        raw: []const u8,
        envelope: Envelope,
    },
};

pub const InboundMessage = struct {
    envelope: Envelope,
    address: std.net.Address, //address of inbound connection (not per se the initiator of the message!)
};

pub fn enqueue_envelope(content: Content, target: Target, server: *udp_server.UDPServer) !void {
    switch (target) {
        .id => |id| {
            const envelope = Envelope{
                .source_id = server.id,
                .target_id = id,
                .content = content,
                .nonce = index.id.get_guid(),
            };
            try server.job_queue.enqueue(.{
                .send_message = .{
                    .target = .{ .id = id },
                    .payload = .{ .envelope = envelope },
                },
            });
        },
        .address => |address| {
            const envelope = Envelope{
                .source_id = server.id,
                .content = content,
                .nonce = index.id.get_guid(),
            };
            try server.job_queue.enqueue(.{
                .send_message = .{
                    .target = .{ .address = address },
                    .payload = .{ .envelope = envelope },
                },
            });
        },
    }
}

fn build_reply(content: Content, envelope: Envelope, server_id: ID) !OutboundMessage {
    const reply = Envelope{ .target_id = envelope.source_id, .source_id = server_id, .nonce = envelope.nonce, .content = content };

    const outbound_message = OutboundMessage{
        .target = .{ .id = envelope.source_id },
        .payload = .{
            .envelope = reply,
        },
    };
    return outbound_message;
}

/// >>>>>>>
pub fn process_message(envelope: Envelope, address: std.net.Address, server: *udp_server.UDPServer) !void {
    const content = envelope.content;

    switch (content) {
        .broadcast => |broadcast| {
            std.log.info("got broadcast: '{s}'", .{broadcast});
            for (server.broadcast_hooks.items) |callback| {
                try callback(broadcast, envelope.source_id, address);
            }

            // broadcast further
            try server.job_queue.enqueue(.{ .broadcast = envelope });
        },
        .direct_message => |direct_message| {
            std.log.info("got dm: '{s}'", .{direct_message});
            for (server.direct_message_hooks.items) |callback| {
                try callback(direct_message, envelope.source_id, address);
            }
        },
        .get_known_ips => |n_ips| {
            // sanity check n_ips
            if (n_ips <= 0 or n_ips > 64) {
                return error.TooManyIpsRequested;
            }
            var addresses = try server.routing.select_known_addresses(n_ips);

            const return_content: Content = .{ .send_known_ips = addresses.toOwnedSlice() };
            const outbound_message = try build_reply(return_content, envelope, server.id);

            try server.job_queue.enqueue(.{ .send_message = outbound_message });
        },
        .find => |find| {
            // requester is trying to find a node closest to the search_id
            // We want to figure out if that's us (to our knowledge); if not we pass on the search

            std.log.info("finding: {}", .{find});

            const search_id = find.id;
            if (server.routing.get_closest_record(search_id)) |record| {
                const other_dist = id_.xor(record.id, search_id);
                const our_dist = id_.xor(server.id, search_id);

                if (id_.less(our_dist, other_dist)) {
                    // Return our apparent address as closest

                    const return_content: Content = .{ .found = .{ .id = server.id, .address = server.apparent_address } };
                    const outbound_message = try build_reply(return_content, envelope, server.id);
                    try server.job_queue.enqueue(.{ .send_message = outbound_message });
                } else {
                    // route forward
                    try server.job_queue.enqueue(.{ .send_message = .{ .target = .{ .address = record.address }, .payload = .{ .envelope = envelope } } });
                }
            } else {
                // can't find any record
            }
        },
        .ping => |ping| {
            std.log.info("got ping: {}", .{ping});

            // Resolve the possible connection address

            try server.routing.update_ip_id_pair(envelope.source_id, address);

            std.log.info("got ping from addr: {any}", .{address});
            std.log.info("source id seems: {}", .{index.hex(&envelope.source_id)});

            const return_content: Content = .{ .pong = .{ .apparent_ip = address } };
            const outbound_message = try build_reply(return_content, envelope, server.id);

            std.log.info("reply env: {any}", .{outbound_message.payload});

            try server.job_queue.enqueue(.{ .send_message = outbound_message });
        },
        .pong => |pong| {
            std.log.info("got pong: {} {} {s}", .{ pong, index.hex(&envelope.source_id), address });

            try server.routing.update_ip_id_pair(envelope.source_id, address);
            try server.finger_table.update_ip_id_pair(envelope.source_id, address);
            var our_ip = pong.apparent_ip;
            // our_ip.setPort(server.address.getPort()); // set the port so the address becomes our likely external connection ip
            server.apparent_address = our_ip;
            std.log.info("apparent_address: {}", .{server.apparent_address});
        },
        .found => |found| {
            std.log.info("found result: {s}", .{found});

            const id = found.id;
            if (found.address) |addr| {
                try server.finger_table.set_finger(id, addr);
            } else {
                std.log.info("found, but got no address", .{});
            }
        },
        .send_known_ips => |known_ips| {
            std.log.info("adding n 'known' addresses: {}", .{known_ips.len});

            defer default.allocator.free(known_ips);
            for (known_ips) |addr| {
                try server.routing.add_address_seen(addr);
            }
        },
        .punch_suggest => |punch_suggest| { // Someone is requesting a punch connection
            // send accept invitation
            // this is also an opportunity to possibly suggest another public ip
            // especially if somehow nonce are suggested
            try enqueue_envelope(.{
                .punch_accept = .{
                    .nonce = punch_suggest.nonce,
                    .suggested_public_address = punch_suggest.suggested_public_address,
                },
            }, .{
                .id = envelope.source_id,
            }, server);

            // send suggested ip
            try enqueue_envelope(.{
                .punch_request = .{
                    .nonce = punch_suggest.nonce,
                    .initiator = false,
                },
            }, .{
                .address = punch_suggest.suggested_public_address,
            }, server);
        },
        .punch_accept => |punch_accept| {
            // we got an accept, so now we start the punching as intiator
            try enqueue_envelope(.{
                .punch_request = .{
                    .nonce = punch_accept.nonce,
                    .initiator = true,
                },
            }, .{ .address = punch_accept.suggested_public_address }, server);
        },
        .punch_request => |punch_request| {
            const nonce = punch_request.nonce;
            const initiator = punch_request.initiator;

            if (server.punch_map.get(nonce)) |stored_address| {
                std.log.info("Found a punch between {} {}", .{ address, stored_address });
                if (initiator) {
                    try enqueue_envelope(.{
                        .punch_reply = .{
                            .nonce = punch_request.nonce,
                            .punch_address = stored_address,
                        },
                    }, .{ .address = address }, server);
                } else {
                    try enqueue_envelope(.{
                        .punch_reply = .{
                            .nonce = punch_request.nonce,
                            .punch_address = address,
                        },
                    }, .{ .address = stored_address }, server);
                }

                _ = server.punch_map.remove(nonce);
            } else {
                try server.punch_map.put(nonce, address);
            }
        },
        .punch_reply => |punch_reply| {
            try server.job_queue.enqueue(.{ .connect = punch_reply.punch_address });
        },
    }
}

test "message" {
    const envelope = index.communication_udp.Envelope{
        .content = .{
            .broadcast = "test",
        },
    };

    const slice = try index.serial.serialise(envelope);
    var tmp_slice = slice;
    var x_2 = try index.serial.deserialise(index.communication_udp.Envelope, &tmp_slice);
    const slice2 = try index.serial.serialise(x_2);
    try std.testing.expect(std.mem.eql(u8, slice2, slice));
}
