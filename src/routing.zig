const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;

const Hash = index.Hash;

pub var ip_seen = std.AutoHashMap(Hash, std.net.Address).init(default.allocator);

pub fn add_ip_seen(addr: std.net.Address) !void {
    std.log.info("saw ip: {}", .{addr});
    const addr_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});
    const hash = utils.calculate_hash(addr_string);
    try ip_seen.put(hash, addr);
}
