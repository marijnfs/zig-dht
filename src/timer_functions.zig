// Staging area; where new functions that don't have a place yet can be put

const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const communication = index.communication_udp;
const id_ = index.id;
const UDPServer = index.UDPServer;
const ID = index.ID;

pub fn expand_connections(_: *UDPServer) !void {
    // Request more known ips
    // var it = default.server.outgoing_connections.keyIterator();
    // while (it.next()) |conn| {
    //     std.log.info("conn: {}", .{conn.*.address});
    //     const content: communication.Content = .{ .get_known_ips = default.target_connections };
    //     const envelope = communication.Envelope{ .target_id = std.mem.zeroes(ID), .source_id = default.server.id, .nonce = id_.get_guid(), .content = content };

    //     const outbound_message = communication.OutboundMessage{
    //         .target = .{ .guid = conn.*.guid },
    //         .payload = .{
    //             .envelope = envelope,
    //         },
    //     };

    //     try default.server.job_queue.enqueue(.{ .send_message = outbound_message });
    // }

    // const connections_to_add = default.target_connections - n_connections;

    // const addresses_seen = try routing.get_addresses_seen();
    // defer default.allocator.free(addresses_seen);

    // const random_selection = try utils.random_selection(connections_to_add, addresses_seen.len);
    // defer default.allocator.free(random_selection);

    // for (random_selection) |s| {
    //     const address = addresses_seen[s];
    //     if (default.server.is_connected_to(address))
    //         continue;
    //     try default.server.job_queue.enqueue(.{ .connect = address });
    // }
}

pub fn sync_finger_table(server: *UDPServer) !void {
    var it = server.routing.finger_table.iterator();
    while (it.next()) |finger| {
        const id = finger.key_ptr.*;
        const node = finger.value_ptr.*;
        if (id_.is_zero(node.id))
            continue;
        const address = node.address;

        std.log.info("connecting to finger: {} {}", .{ utils.hex(&id), node });
        try server.job_queue.enqueue(.{ .connect = address });
    }
}

pub fn refresh_finger_table(server: *UDPServer) !void {
    var it = server.routing.finger_table.keyIterator();
    while (it.next()) |id| {
        const content: communication.Content = .{ .find = .{ .id = id.*, .inclusive = 1 } };
        const envelope = communication.Envelope{ .target_id = std.mem.zeroes(ID), .source_id = server.id, .nonce = id_.get_guid(), .content = content };

        const outbound_message = communication.OutboundMessage{
            .target = .{ .id = id.* },
            .payload = .{
                .envelope = envelope,
            },
        };

        try server.job_queue.enqueue(.{ .send_message = outbound_message });
    }
}

pub fn count_connections() usize {
    var n_connections = default.server.outgoing_connections.count();

    // Also count the soon to be connections
    for (default.server.job_queue.queue.slice()) |job_ptr| {
        if (job_ptr.* == .connect) {
            n_connections += 1;
        }
    }
    return n_connections;
}
