const std = @import("std");
usingnamespace @import("index.zig");

// Message contents

pub const Data = union(enum) { ping: struct {
    source_id: ID,
}, pong: struct {
    source_id: ID,
    apparent_ip: std.net.Address,
} };
