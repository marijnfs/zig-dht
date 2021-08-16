const std = @import("std");
usingnamespace @import("index.zig");

// Message contents
pub const Message = struct {
    hash: ID = std.mem.zeroes(ID),
    target_id: ID = std.mem.zeroes(ID),
    source_id: ID = std.mem.zeroes(ID),
    content: Content,
};

pub const Content = union(enum) {
    ping: struct {
        source_id: ID,
    },
    pong: struct {
        source_id: ID,
        apparent_ip: std.net.Address,
    },
    raw: []u8,
};
