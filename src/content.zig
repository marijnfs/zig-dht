const std = @import("std");
const index = @import("index.zig");

pub const Content = union(enum) {
    ping: struct {
        id: index.ID,
    },
};
