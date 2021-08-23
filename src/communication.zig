const std = @import("std");
usingnamespace @import("index.zig");

// Message contents
pub const Message = struct {
    hash: ID = std.mem.zeroes(ID), //during forward, this is the hash of the message (minus the hash), during backward it is the reply hash
    target_id: ID = std.mem.zeroes(ID),
    source_id: ID = std.mem.zeroes(ID),
    content: Content,
};

pub const Content = union(enum) {
    ping: struct {
        source_id: ID,
    },
    pong: struct {
        source_id: ID,
        apparent_ip: std.net.Address,
    },
    raw: []u8,
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
    guid: u64,
    content: []u8,
};

/// >>>>>>>
/// >>>>>>>
pub fn process_forward(message: communication.Message, guid: u64) !void {
    const content = message.content;

    switch (content) {
        .ping => |ping| {
            std.log.info("got ping: {}", .{ping});
            const conn = try default.server.get_incoming_connection(guid);
            const addr = conn.address();
            std.log.info("ping Addr: {any}", .{addr});

            const return_message = communication.Message{ .target_id = ping.source_id, .source_id = default.server.id, .content = .{ .pong = .{ .source_id = default.server.id, .apparent_ip = addr } } };

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
            conn.id = pong.source_id;
            std.log.info("setting source id, for {s}: {any}", .{ addr, conn.id });
        },
        else => {
            std.log.warn("invalid forward message {any}", .{message});
        },
    }
}
