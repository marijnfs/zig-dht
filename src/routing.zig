const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;

const ID = index.ID;
const Hash = index.Hash;

pub var addresses_seen = std.AutoHashMap(Hash, std.net.Address).init(default.allocator);

const FINGERS = 8;
pub var finger_table = std.AutoHashMap(ID, struct {
    id: ID = std.mem.zeroes(ID),
    address: std.net.Address = undefined,
}).init(default.allocator);

pub fn init_finger_table() !void {
    var i: usize = 0;
    std.log.info("finger table init, id is: {any}", .{default.server.id});
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
