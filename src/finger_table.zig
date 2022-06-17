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
};

pub const FingerTable = struct {
    id: ID,

    finger_table: std.AutoHashMap(ID, Finger),

    pub fn init(id: ID, n_fingers: usize) !*FingerTable {
        var table = try default.allocator.create(FingerTable);
        table.* = .{
            .id = id,
            .finger_table = std.AutoHashMap(ID, Finger).init(default.allocator),
        };

        try table.init_finger_table(n_fingers);
        return table;
    }

    pub fn deinit(table: *FingerTable) void {
        table.finger_table.deinit();
    }

    pub fn init_finger_table(table: *FingerTable, n_fingers: usize) !void {
        var i: usize = 0;
        std.log.info("finger table init, id is: {}", .{index.hex(&table.id)});
        while (i < n_fingers) : (i += 1) {
            const id = id_.xor_bitpos(table.id, i);
            std.log.info("id[{}]: {}", .{ i, index.hex(&id) });
            if (!table.finger_table.contains(id))
                try table.finger_table.put(id, .{});
        }
    }

    pub fn set_finger(table: *FingerTable, id: ID, address: std.net.Address) !void {
        if (!table.finger_table.contains(id)) {
            return error.InvalidFinger;
        }

        const closest_id = try table.get_closest_id(id);
        try table.finger_table.put(closest_id, .{ .id = id, .address = address });
        std.log.info("put id {} {}", .{ index.hex(&id), address });
    }

    pub fn get_closest_id(table: *FingerTable, id: ID) !ID {
        var it = table.finger_table.valueIterator();

        var closest = std.mem.zeroes(ID);
        var closest_id = std.mem.zeroes(ID);

        while (it.next()) |finger| {
            const finger_id = finger.*.id;
            if (id_.is_zero(finger_id)) //value is not set yet,
                continue;
            const distance = id_.xor(id, finger_id);
            if (id_.is_zero(closest) or id_.less(distance, closest)) {
                closest = distance;
                closest_id = finger_id;
            }
        }

        if (id_.is_zero(closest_id))
            return error.NoClosestIdFound;
        return closest_id;
    }

    pub fn get_closest_finger(table: *FingerTable, id: ID) ?Finger {
        const closest_id = table.get_closest_id(id) catch return null;
        return table.finger_table.get(closest_id);
    }

    pub fn iterator(table: *FingerTable) std.AutoHashMap(ID, Finger).Iterator {
        return table.finger_table.iterator();
    }

    pub fn keyIterator(table: *FingerTable) std.AutoHashMap(ID, Finger).KeyIterator {
        return table.finger_table.keyIterator();
    }

    pub fn valueIterator(table: *FingerTable) std.AutoHashMap(ID, Finger).ValueIterator {
        return table.finger_table.valueIterator();
    }
};
