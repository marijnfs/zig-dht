const std = @import("std");

const index = @import("index.zig");
const default = index.default;

const ID = index.ID;

pub var hashes_seen: std.AutoHashMap(ID, void) = undefined;

pub fn init() void {
    hashes_seen = std.AutoHashMap(ID, void).init(default.allocator);
}

pub fn add_hash(hash: ID) !void {
    try hashes_seen.put(hash, {});
}

pub fn check_hash(hash: ID) bool {
    return hashes_seen.get(hash).found_existing;
}

pub fn check_and_add_hash(hash: ID) !bool {
    if (index.id.is_zero(hash)) {
        return error.CheckHashIsZero;
    }
    return (try hashes_seen.getOrPut(hash)).found_existing;
}
