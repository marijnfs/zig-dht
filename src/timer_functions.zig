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
        try communication.enqueue_envelope(.{ .ping = .{ .public = server.public } }, .{ .address = address.* }, server);

        // try server.job_queue.enqueue(.{ .connect = .{ .address = address.*, .public = true } });
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

    var id_set = std.AutoHashMap(ID, bool).init(index.default.allocator);
    defer id_set.deinit();

    while (it.next()) |finger| {
        const id = finger.key_ptr.*;
        const node = finger.value_ptr;

        const require_public = false;
        if (server.routing.get_closest_active_record(id, require_public)) |record| {
            if (id_set.get(record.id)) |_| {
                node.id = id_.zeroes();
            } else {
                try id_set.put(record.id, true);

                node.id = record.id;
                node.address = record.address;
            }
        }
    }

    var id_set_public = std.AutoHashMap(ID, bool).init(index.default.allocator);
    defer id_set_public.deinit();

    var it_public = server.public_finger_table.iterator();
    while (it_public.next()) |finger| {
        const id = finger.key_ptr.*;
        const node = finger.value_ptr;

        const require_public = true;
        if (server.routing.get_closest_active_record(id, require_public)) |record| {
            if (id_set_public.get(record.id)) |_| {
                node.id = id_.zeroes();
            } else {
                try id_set_public.put(record.id, true);

                node.id = record.id;
                node.address = record.address;
            }
        }
    }
}

pub fn ping_finger_table(server: *Server) !void {
    std.log.debug("ping finger table", .{});

    const ping_fingers = struct {
        fn f(it: anytype, server_: *Server) !void {
            while (it.next()) |finger| {
                const id = finger.key_ptr.*;
                const node = finger.value_ptr.*;

                if (id_.is_zero(node.id))
                    continue;

                std.log.debug("pinging finger: {} {}", .{ index.hex(&id), node });
                const address = node.address;

                try communication.enqueue_envelope(.{ .ping = .{ .public = server_.public } }, .{ .address = address }, server_);
            }
        }
    }.f;

    var it = server.finger_table.iterator();
    var public_it = server.public_finger_table.iterator();
    try ping_fingers(&it, server);
    try ping_fingers(&public_it, server);
}

pub fn search_finger_table(server: *Server) !void {
    std.log.debug("search finger table", .{});
    {
        var it = server.finger_table.keyIterator();
        while (it.next()) |id| {
            const content: communication.Content = .{ .find = .{ .id = id.*, .inclusive = 1 } };
            try communication.enqueue_envelope(content, .{ .id = id_.zeroes() }, server);
        }
    }
    // update public table
    {
        var it = server.public_finger_table.keyIterator();
        while (it.next()) |id| {
            const content: communication.Content = .{ .find = .{ .id = id.*, .inclusive = 1, .public = true } };
            try communication.enqueue_envelope(content, .{ .id = id_.zeroes() }, server);
        }
    }
}
