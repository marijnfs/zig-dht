// Staging area; where new functions that don't have a place yet can be put

const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;
const routing = index.routing;
const utils = index.utils;

pub fn expand_connections() !void {
    const n_connections = count_connections();
    std.log.info("n connection: {}", .{n_connections});

    if (n_connections > default.target_connections)
        return;

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

pub fn sync_finger_table() !void {}

pub fn refresh_finger_table() !void {}

pub fn count_connections() usize {
    var n_connections = default.server.incoming_connections.count();

    // Also count the soon to be connections
    for (jobs.job_queue.slice()) |job| {
        if (job == .connect) {
            n_connections += 1;
        }
    }
    return n_connections;
}

// pub fn clear_closed_connections(server: *Server) void {
// Todo, don't use remove inside loop; invadlidates the iterator

// var it_in = server.incoming_connections.keyIterator();
// while (it_in.next()) |conn| {
//     if (conn.*.state == .Disconnected)
//         server.out_going_connections.remove(conn.*);
// }

// var it_out = server.outgoing_connections.keyIterator();
// while (it_out.next()) |conn| {
//     if (conn.*.state == .Disconnected)
//         server.out_going_connections.remove(conn.*);
// }
// }
