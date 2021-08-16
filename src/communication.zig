const std = @import("std");
usingnamespace @import("index.zig");

// Message contents
pub const Message = struct {
    hash: ID,
    target_id: ID,
    source_id: ID,
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
