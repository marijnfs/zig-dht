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

// network discovery, simply ping all seen addresses
// Todo, this is quite brute force, make smarter
pub fn ping_addresses_seen(server: *Server) !void {
    var it = server.routing.addresses_seen.valueIterator();
    while (it.next()) |address| {
        try communication.enqueue_envelope(.{ .ping = .{ .public = server.public } }, .{ .address = address.* }, server);

        // try server.job_queue.enqueue(.{ .connect = .{ .address = address.*, .public = true } });
    }
}

pub fn discover_addresses_seen(server: *Server) !void {
    var it = server.finger_table.iterator();
    while (it.next()) |finger| {
        const node = finger.value_ptr;
        if (!node.is_zero())
            try communication.enqueue_envelope(.{ .get_known_ips = 8 }, .{ .address = node.address }, server);
    }
}

pub fn sync_finger_table_with_routing(server: *Server) !void {
    std.log.debug("Syncing with routing, current active: {}", .{server.finger_table.n_active_connections()});

    for (server.routing.records.items) |kv| {
        std.log.debug("Routing entry: {}", .{kv});
    }

    var id_set = std.AutoHashMap(ID, bool).init(default.allocator);
    defer id_set.deinit();

    var it = server.finger_table.iterator();

    while (it.next()) |kv| {
        const key = kv.key_ptr.*;
        const finger = kv.value_ptr;

        const require_public = false;
        if (server.routing.get_closest_active_record(key, require_public)) |record| {
            if ((try id_set.getOrPut(record.id)).found_existing) {
                finger.id = id_.zeroes();
            } else {
                finger.id = record.id;
                finger.address = record.address;
            }
        }
    }
    id_set.clearRetainingCapacity();

    var it_public = server.public_finger_table.iterator();
    while (it_public.next()) |kv| {
        const key = kv.key_ptr.*;
        const finger = kv.value_ptr;

        const require_public = true;
        if (server.routing.get_closest_active_record(key, require_public)) |record| {
            if ((try id_set.getOrPut(record.id)).found_existing) {
                finger.id = id_.zeroes();
            } else {
                finger.id = record.id;
                finger.address = record.address;
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

                try server_.job_queue.enqueue(.{ .connect = .{ .address = address, .public = server_.public } });
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
