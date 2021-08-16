const std = @import("std");

usingnamespace @import("index.zig");

var hashes_seen = std.AutoHashMap(ID).init(default.allocator);
