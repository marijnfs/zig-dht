const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const id_ = index.id;

const ID = index.ID;
const Hash = index.Hash;

const Finger = struct {
    id: ID = std.mem.zeroes(ID),
    address: std.net.Address = undefined,

    pub fn is_zero(finger: *const Finger) bool {
        return id_.is_zero(finger.id);
    }
};

pub const FingerTable = struct {
    id: ID,

    fingers: std.AutoHashMap(ID, Finger),

    pub fn init(id: ID, n_fingers: usize) !*FingerTable {
        var table = try default.allocator.create(FingerTable);
        table.* = .{
            .id = id,
            .fingers = std.AutoHashMap(ID, Finger).init(default.allocator),
        };

        try table.init_finger_table(n_fingers);
        return table;
    }

    pub fn deinit(table: *FingerTable) void {
        table.fingers.deinit();
    }

    pub fn update_closest_finger(table: *FingerTable, id: ID, address: std.net.Address) !void {
        if (table.get_closest_finger(id)) |finger| {
            finger.* = .{ .id = id, .address = address };
        }
    }

    pub fn get_closest_finger(table: *FingerTable, id: ID) ?*Finger {
        const closest_id = table.get_closest_key(id) catch return null;
        return table.fingers.getPtr(closest_id);
    }

    pub fn get_closest_active_finger(table: *FingerTable, id: ID) ?*Finger {
        var it = table.iterator();
        var closest_finger: *Finger = undefined;
        var closest_distance = id_.ones();
        while (it.next()) |kv| {
            const key = kv.key_ptr.*;
            const finger = kv.value_ptr;
            if (finger.is_zero())
                continue;
            const distance = id_.xor(id, key);
            if (id_.less(distance, closest_distance)) {
                closest_distance = distance;
                closest_finger = finger;
            }
        }

        if (id_.is_ones(closest_distance))
            return null;
        return closest_finger;
    }

    pub fn get_random_active_finger(table: *FingerTable) !?Finger {
        var active_fingers = std.ArrayList(*Finger).init(default.allocator);
        defer active_fingers.deinit();

        var it = table.valueIterator();
        while (it.next()) |finger| {
            if (!finger.is_zero()) {
                try active_fingers.append(finger);
            }
        }

        if (active_fingers.items.len == 0) {
            std.log.debug("Didn't find random active finger", .{});
            return null;
        }

        var selection = try utils.random_selection(1, active_fingers.items.len);
        defer default.allocator.free(selection);

        return active_fingers.items[selection[0]].*;
    }

    pub fn get_closest_key(table: *FingerTable, id: ID) !ID {
        var it = table.fingers.keyIterator();

        var closest_distance = id_.ones();
        var closest_id = std.mem.zeroes(ID);

        while (it.next()) |key| {
            const distance = id_.xor(id, key.*);
            if (id_.less(distance, closest_distance)) {
                closest_distance = distance;
                closest_id = key.*;
            }
        }

        if (id_.is_ones(closest_id))
            return error.NoClosestIdFound;
        return closest_id;
    }

    pub fn iterator(table: *FingerTable) std.AutoHashMap(ID, Finger).Iterator {
        return table.fingers.iterator();
    }

    pub fn keyIterator(table: *FingerTable) std.AutoHashMap(ID, Finger).KeyIterator {
        return table.fingers.keyIterator();
    }

    pub fn valueIterator(table: *FingerTable) std.AutoHashMap(ID, Finger).ValueIterator {
        return table.fingers.valueIterator();
    }

    pub fn count(table: *FingerTable) usize {
        return table.fingers.count();
    }

    pub fn n_active_connections(table: *FingerTable) usize {
        var n_active: usize = 0;
        var it = table.fingers.valueIterator();

        while (it.next()) |finger| {
            if (!finger.is_zero())
                n_active += 1;
        }
        return n_active;
    }

    fn closer_to_me(table: *FingerTable, id: ID, id_other: ID) bool {
        const distance = id_.xor(id, table.id);
        const distance_other = id_.xor(id_other, table.id);
        return id_.less(distance, distance_other);
    }

    fn init_finger_table(table: *FingerTable, n_fingers: usize) !void {
        var i: usize = 0;
        std.log.debug("finger table init, id is: {}", .{index.hex(&table.id)});
        while (i < n_fingers) : (i += 1) {
            const id = id_.xor_bitpos(table.id, i);
            std.log.debug("id[{}]: {}", .{ i, index.hex(&id) });
            if (!table.fingers.contains(id))
                try table.fingers.put(id, .{});
        }
    }
};
