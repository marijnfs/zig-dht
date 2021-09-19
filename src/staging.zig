// Staging area; where new functions that don't have a place yet can be put

const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;
const routing = index.routing;
const utils = index.utils;
const communication = index.communication;

const ID = index.ID;

pub fn expand_connections() !void {
    const n_connections = count_connections();

    std.log.info("n connection: {}", .{n_connections});
    // We're good
    if (n_connections > default.target_connections)
        return;

    // Request more known ips
    var it = default.server.outgoing_connections.keyIterator();
    while (it.next()) |conn| {
        std.log.info("conn: {}", .{conn.*.address});
        const content: communication.Content = .{ .get_known_ips = default.target_connections };
        const message = communication.Message{ .target_id = std.mem.zeroes(ID), .source_id = default.server.id, .nonce = utils.get_guid(), .content = content };

        const envelope = communication.Envelope{
            .target = .{ .guid = conn.*.guid },
            .payload = .{
                .message = message,
            },
        };

        try jobs.enqueue(.{ .send_message = envelope });
    }

    const connections_to_add = default.target_connections - n_connections;

    const addresses_seen = try routing.get_addresses_seen();
    defer default.allocator.free(addresses_seen);

    const random_selection = try utils.random_selection(connections_to_add, addresses_seen.len);
    defer default.allocator.free(random_selection);

    for (random_selection) |s| {
        const address = addresses_seen[s];
        if (default.server.is_connected_to(address))
            continue;
        try jobs.enqueue(.{ .connect = address });
    }
}

pub fn sync_finger_table() !void {
    var it = routing.finger_table.iterator();
    while (it.next()) |finger| {
        const id = finger.key_ptr.*;
        const node = finger.value_ptr.*;
        if (utils.id_is_zero(node.id))
            continue;
        const address = node.address;
        if (default.server.is_connected_to(address))
            continue;

        std.log.info("connecting to finger: {} {}", .{ utils.hex(&id), node });
        try jobs.enqueue(.{ .connect = address });
    }
}

pub fn refresh_finger_table() !void {
    var it = routing.finger_table.keyIterator();
    while (it.next()) |id| {
        const content: communication.Content = .{ .find = .{ .id = id.*, .inclusive = 1 } };
        const message = communication.Message{ .target_id = std.mem.zeroes(ID), .source_id = default.server.id, .nonce = utils.get_guid(), .content = content };

        const envelope = communication.Envelope{
            .target = .{ .id = id.* },
            .payload = .{
                .message = message,
            },
        };

        try jobs.enqueue(.{ .send_message = envelope });
    }
}

pub fn detect_self_connection() !void {
    var it = default.server.outgoing_connections.keyIterator();
    while (it.next()) |conn| {
        std.log.info("comparing {} {}", .{ conn.*.address, default.server.apparent_address });
        if (std.net.Address.eql(conn.*.address, default.server.apparent_address)) {
            conn.*.close();
            _ = default.server.outgoing_connections.remove(conn.*);
        }
    }
}

pub fn count_connections() usize {
    var n_connections = default.server.outgoing_connections.count();

    // Also count the soon to be connections
    for (jobs.job_queue.slice()) |job| {
        if (job == .connect) {
            n_connections += 1;
        }
    }
    return n_connections;
}

pub fn clear_closed_connections() !void {
    // Todo, don't use remove inside loop; invadlidates the iterator

    try default.server.clean_incoming_connections();
    try default.server.clean_outgoing_connections();
}
