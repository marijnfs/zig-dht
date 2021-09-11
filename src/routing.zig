const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;

const Hash = index.Hash;

pub var addresses_seen = std.AutoHashMap(Hash, std.net.Address).init(default.allocator);

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

pub fn add_ip_seen(addr: std.net.Address) !void {
    std.log.info("saw ip: {}", .{addr});
    const addr_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});
    const hash = utils.calculate_hash(addr_string);
    try addresses_seen.put(hash, addr);
}
