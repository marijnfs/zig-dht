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

pub const RoutingTable = struct {
    id: ID,
    addresses_seen: std.AutoHashMap(Hash, std.net.Address),
    finger_table: std.AutoHashMap(ID, Finger),

    pub fn init(id: ID, n_fingers: usize) !*RoutingTable {
        var table = try default.allocator.create(RoutingTable);
        table.id = id;
        table.addresses_seen = std.AutoHashMap(Hash, std.net.Address).init(default.allocator);
        table.finger_table = std.AutoHashMap(ID, Finger).init(default.allocator);

        try table.init_finger_table(n_fingers);
        return table;
    }

    pub fn deinit(table: *RoutingTable) void {
        table.addresses_seen.deinit();
        table.finger_table.deinit();
    }

    pub fn init_finger_table(table: *RoutingTable, n_fingers: usize) !void {
        var i: usize = 0;
        std.log.info("finger table init, id is: {}", .{utils.hex(&table.id)});
        while (i < n_fingers) : (i += 1) {
            const id = id_.xor_bitpos(table.id, i);
            if (!table.finger_table.contains(id))
                try table.finger_table.put(id, .{});
        }
    }

    pub fn get_addresses_seen(table: *RoutingTable) ![]std.net.Address {
        var addresses = try default.allocator.alloc(std.net.Address, table.addresses_seen.count());
        var it = table.addresses_seen.valueIterator();

        var i: usize = 0;
        while (it.next()) |address| {
            addresses[i] = address.*;
            i += 1;
        }
        return addresses;
    }

    pub fn add_address_seen(table: *RoutingTable, addr: std.net.Address) !void {
        std.log.info("saw ip: {}", .{addr});
        const addr_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});
        const hash = utils.calculate_hash(addr_string);
        try table.addresses_seen.put(hash, addr);
    }

    pub fn set_finger(table: *RoutingTable, id: ID, address: std.net.Address) !void {
        if (!table.finger_table.contains(id)) {
            return error.InvalidFinger;
        }

        const closest_id = try table.get_closest_id(id);
        try table.finger_table.put(closest_id, .{ .id = id, .address = address });
        std.log.info("put id {} {}", .{ utils.hex(&id), address });
    }

    pub fn get_closest_id(table: *RoutingTable, id: ID) !ID {
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

    fn iter_finger_table(table: *RoutingTable) std.AutoHashMap(ID, Finger).Iterator {
        return table.finger_table.iterator();
    }
};

test "Basics" {
    var routing = try RoutingTable.init(index.id.rand_id(), 8);
    defer routing.deinit();

    var adresses = try routing.get_addresses_seen();
    try std.testing.expect(adresses.len == 0);

    var count: usize = 0;
    var iter = routing.iter_finger_table();
    while (iter.next()) |kv| {
        count += 1;
        std.log.info("{}", .{kv});
    }
    try std.testing.expect(count == 8);
}
