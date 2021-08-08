const std = @import("std");
const index = @import("index.zig");

// Message contents

pub const Data = union(enum) {
    ping: struct {
        id: index.ID,
    },
};
