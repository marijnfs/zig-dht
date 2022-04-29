// Bot, little state machines with behaviour and accompanying scheduling queue

const std = @import("std");
const index = @import("index.zig");
const default = index.default;

pub const Bot = union(enum) {
    iterate: struct {
        n: usize,
    },
};

pub fn step(bot: Bot) void {
    switch (bot) {
        .iterate => {
            std.log.info("iterate", .{});
        },
    }
}

pub fn createIterate() Bot {
    return .{ .iterate = .{ .n = 0 } };
}
