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
        source_id: ID,
        source_port: u16,
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
    broadcast: []const u8,
};

pub const Envelope = struct {
    hash: ID = std.mem.zeroes(ID), //during forward, this is the hash of the message (minus the hash), during backward it is the reply hash
    target_id: ID = std.mem.zeroes(ID),
    source_id: ID = std.mem.zeroes(ID),
    nonce: u64 = 0,
    content: Content,
};

pub const OutboundMessage = struct {
    target: union(enum) {
        id: ID,
        address: std.net.Address,
    }, //target output node
    payload: union(enum) {
        raw: []const u8,
        envelope: Envelope,
    },
};

pub const InboundMessage = struct {
    envelope: Envelope,
    address: std.net.Address, //address of inbound connection (not per se the initiator of the message!)
};

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
            std.log.info("broadcast: '{s}'", .{broadcast});
            // try c.update_user(.{
            //     .username = broadcast.username,
            //     .row = broadcast.row,
            //     .col = broadcast.col,
            //     .char = broadcast.char,
            //     .msg = broadcast.msg,
            //     .id = broadcast.id,
            // });
            // try server.job_queue.enqueue(.{ .broadcast = broadcast });
            // try server.job_queue.enqueue(.{ .render = true });
        },
        .get_known_ips => |n_ips| {
            // sanity check n_ips

            var addresses = std.ArrayList(std.net.Address).init(default.allocator);
            defer addresses.deinit();
            for (server.records.items) |record| {
                try addresses.append(record.address);
            }

            var selection = try utils.random_selection(n_ips, addresses.items.len);
            defer default.allocator.free(selection);

            var ips = try default.allocator.alloc(std.net.Address, selection.len);

            var i: usize = 0;
            for (selection) |s| {
                ips[i] = addresses.items[s];
                i += 1;
            }

            const return_content: Content = .{ .send_known_ips = ips };
            const outbound_message = try build_reply(return_content, envelope, server.id);

            try server.job_queue.enqueue(.{ .send_message = outbound_message });
        },
        .find => |find| {
            // requester is trying to find a node closest to the search_id
            // We want to figure out if that's us (to our knowledge); if not we pass on the search

            std.log.info("finding: {}", .{find});

            const search_id = find.id;
            if (server.get_closest_record(search_id)) |record| {
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
            var addr = address;
            addr.setPort(ping.source_port);

            try server.update_ip_id_pair(addr, envelope.source_id);

            std.log.info("got ping from addr: {any}", .{addr});
            std.log.info("source id seems: {}", .{utils.hex(&envelope.source_id)});

            const return_content: Content = .{ .pong = .{ .apparent_ip = addr } };
            const outbound_message = try build_reply(return_content, envelope, server.id);

            std.log.info("reply env: {any}", .{outbound_message.payload});

            try server.job_queue.enqueue(.{ .send_message = outbound_message });
        },
        .pong => |pong| {
            std.log.info("got pong: {}", .{pong});

            var our_ip = pong.apparent_ip;
            our_ip.setPort(server.address.getPort()); // set the port so the address becomes our likely external connection ip
            server.apparent_address = our_ip;
        },
        .found => |found| {
            std.log.info("found result: {s}", .{found});

            const id = found.id;
            if (found.address) |addr| {
                try routing.set_finger(id, addr);
            } else {
                std.log.info("found, but got no address", .{});
            }
        },
        .send_known_ips => |known_ips| {
            std.log.info("adding n 'known' addresses: {}", .{known_ips.len});

            defer default.allocator.free(known_ips);
            for (known_ips) |addr| {
                try routing.add_address_seen(addr);
            }
        },
    }
}
