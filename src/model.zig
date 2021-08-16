const std = @import("std");

usingnamespace @import("index.zig");

pub var hashes_seen = std.AutoHashMap(ID, void).init(default.allocator);
