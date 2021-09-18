const std = @import("std");

const index = @import("index.zig");
const default = index.default;

const ID = index.ID;

pub var hashes_seen: std.AutoHashMap(ID, void) = undefined;

pub fn init() void {
    hashes_seen = std.AutoHashMap(ID, void).init(default.allocator);
}
