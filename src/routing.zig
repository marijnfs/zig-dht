const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;

const ID = index.ID;
const Hash = index.Hash;

pub var addresses_seen = std.AutoHashMap(Hash, std.net.Address).init(default.allocator);

// Finger table
const FINGERS = 1;

const Finger = struct {
    id: ID = std.mem.zeroes(ID),
    address: std.net.Address = undefined,
};

pub var finger_table = std.AutoHashMap(ID, Finger).init(default.allocator);

pub fn init_finger_table() !void {
    var i: usize = 0;
    std.log.info("finger table init, id is: {}", .{utils.hex(&default.server.id)});
    while (i < FINGERS) : (i += 1) {
        const id = utils.get_finger_id(default.server.id, i);
        if (!finger_table.contains(id))
            try finger_table.put(id, .{});
    }
}

pub fn get_addresses_seen() ![]std.net.Address {
    var addresses = try default.allocator.alloc(std.net.Address, addresses_seen.count());
    var it = addresses_seen.valueIterator();

    var i: usize = 0;
    while (it.next()) |address| {
        addresses[i] = address.*;
        i += 1;
    }
    return addresses;
}

pub fn add_address_seen(addr: std.net.Address) !void {
    std.log.info("saw ip: {}", .{addr});
    const addr_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});
    const hash = utils.calculate_hash(addr_string);
    try addresses_seen.put(hash, addr);
}

pub fn set_finger(id: ID, address: std.net.Address) !void {
    if (!finger_table.contains(id)) {
        return error.InvalidFinger;
    }

    const closest_id = try get_closest_id(id);
    try finger_table.put(closest_id, .{ .id = id, .address = address });
}

pub fn get_closest_id(id: ID) !ID {
    var it = finger_table.valueIterator();

    var closest = std.mem.zeroes(ID);
    while (it.next()) |value| {
        if (utils.id_is_zero(value.*.id)) //value is not set yet,
            continue;
        const distance = utils.xor(id, value.*.id);
        if (utils.id_is_zero(closest)) //always set
            closest = distance;

        if (utils.less(distance, closest))
            closest = distance;
    }

    if (utils.id_is_zero(closest))
        return error.NoClosestIdFound;
    return closest;
}
