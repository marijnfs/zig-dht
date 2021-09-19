const std = @import("std");
const stdin = std.io.getStdIn().reader();
const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;
const communication = index.communication;
const utils = index.utils;

var readline_frame: @Frame(readline_thread_function) = undefined;

pub fn readline_thread_function() !void {
    var buf: [999]u8 = undefined;
    while (true) {
        const user_input = try stdin.readUntilDelimiterOrEof(buf[0..], '\n');
        const content = communication.Content{ .broadcast = user_input.? };
        const message = communication.Message{ .source_id = default.server.id, .nonce = utils.get_guid(), .content = content };

        try jobs.enqueue(.{ .broadcast = message });
    }
}

pub fn start_readline_thread() !void {
    // readline_thread = try std.Thread.spawn(.{}, readline_thread_function, .{});
    readline_frame = async readline_thread_function();
}
