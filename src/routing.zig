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

const Record = struct {
    id: ID = std.mem.zeroes(ID),
    address: net.Address = undefined,
    red_flags: usize = 0,
    last_connect: i64 = 0,
};

pub const RoutingTable = struct {
    id: ID,
    addresses_seen: std.AutoHashMap(Hash, std.net.Address),
    finger_table: std.AutoHashMap(ID, Finger),

    records: std.ArrayList(*Record),
    ip_index: std.StringHashMap(*Record),
    id_index: std.AutoHashMap(ID, *Record),

    pub fn init(id: ID, n_fingers: usize) !*RoutingTable {
        var table = try default.allocator.create(RoutingTable);
        table.* = .{
            .id = id,
            .addresses_seen = std.AutoHashMap(Hash, std.net.Address).init(default.allocator),
            .finger_table = std.AutoHashMap(ID, Finger).init(default.allocator),

            .records = std.ArrayList(*Record).init(default.allocator),
            .ip_index = std.StringHashMap(*Record).init(default.allocator),
            .id_index = std.AutoHashMap(ID, *Record).init(default.allocator),
        };

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

    fn verify_address(table: *RoutingTable, address: net.Address) !bool {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{address});
        if (table.ip_index.get(ip_string)) |record| {
            //known
            record.last_connect = time.milliTimestamp();
            if (record.red_flags > 1) //drop message
            {
                std.log.info("Dropping red-flag message, flags: {}", .{record.red_flags});
                return false;
            }
        } else {
            var record = try default.allocator.create(Record);
            record.* = .{
                .address = address,
                .last_connect = time.milliTimestamp(),
            };

            try table.records.append(record);
            try table.ip_index.put(ip_string, record);
        }
        return true;
    }

    pub fn get_record_by_ip(table: *RoutingTable, address: std.net.Address) ?Record {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{address});
        return table.ip_index.get(ip_string);
    }

    pub fn get_record_by_id(table: *RoutingTable, id: ID) ?Record {
        return table.id_index.get(id);
    }

    pub fn update_ip_id_pair(table: *RoutingTable, addr: std.net.Address, id: ID) !void {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});

        if (table.ip_index.get(ip_string)) |record| {
            record.id = id;

            try table.id_index.put(id, record);
            try table.ip_index.put(ip_string, record);
        } else {
            // create new record
            var record = try default.allocator.create(Record);
            record.* = .{
                .id = id,
                .address = addr,
                .last_connect = time.milliTimestamp(),
            };
            try table.records.append(record);

            try table.id_index.put(id, record);
            try table.ip_index.put(ip_string, record);
        }
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
