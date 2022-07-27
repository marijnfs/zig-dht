// Staging area; where new functions that don't have a place yet can be put

const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const communication = index.communication;
const id_ = index.id;
const Server = index.Server;
const ID = index.ID;
const hex = index.hex;

pub fn bootstrap_connect_seen(server: *Server) !void {
    var it = server.routing.addresses_seen.valueIterator();
    while (it.next()) |address| {
        try server.job_queue.enqueue(.{ .connect = address.* });
    }
}

pub fn sync_finger_table_with_routing(server: *Server) !void {
    //TODO: Make sure n_active_connections keeps 'last connect' into account
    // Needs heartbeat
    std.log.debug("Syncing with routing, current active: {}", .{server.finger_table.n_active_connections()});

    for (server.routing.records.items) |kv| {
        std.log.debug("Routing entry: {}", .{kv});
    }

    var it = server.finger_table.iterator();
    while (it.next()) |finger| {
        const id = finger.key_ptr.*;
        const node = finger.value_ptr;

        if (server.routing.get_closest_active_record(id)) |*record| {
            node.id = record.id;
            node.address = record.address;
        }
    }
}

pub fn ping_finger_table(server: *Server) !void {
    std.log.debug("ping finger table", .{});
    var it = server.finger_table.iterator();
    while (it.next()) |finger| {
        const id = finger.key_ptr.*;
        const node = finger.value_ptr.*;

        if (id_.is_zero(node.id))
            continue;

        std.log.debug("Connecting to finger: {} {}", .{ index.hex(&id), node });
        const address = node.address;

        try server.job_queue.enqueue(.{ .connect = address });
    }
}

pub fn search_finger_table(server: *Server) !void {
    std.log.info("search finger table", .{});
    {
        var it = server.finger_table.keyIterator();
        while (it.next()) |id| {
            const content: communication.Content = .{ .find = .{ .id = id.*, .inclusive = 1 } };
            try communication.enqueue_envelope(content, .{ .id = id.* }, server);
        }
    }
    // update public table
    {
        var it = server.public_finger_table.keyIterator();
        while (it.next()) |id| {
            const content: communication.Content = .{ .find = .{ .id = id.*, .inclusive = 1, .public = true } };
            try communication.enqueue_envelope(content, .{ .id = id.* }, server);
        }
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
