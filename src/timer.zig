const std = @import("std");

usingnamespace @import("index.zig");

const Timer = struct { alarm: i64 = 0, callback: fn () void, delay: i64 = 0 };

fn compare_timer(t1: Timer, t2: Timer) std.math.Order {
    if (t1.alarm < t2.alarm) return .lt else return .gt;
}

var queue = std.PriorityQueue(Timer).init(default.allocator, compare_timer);

var timer_thread: std.Thread = undefined;

pub fn timer_thread_function() !void {
    while (true) {
        if (queue.peek()) |*timer_| {
            if (std.time.timestamp() > timer_.alarm) {
                timer_.callback();

                if (timer_.delay > 0) {
                    timer_.alarm += timer_.delay;
                    try queue.add(timer_.*);
                }
            }
        } else {
            std.time.sleep(1000); // short sleep
        }
    }
}

pub fn start_timer_thread() !void {
    timer_thread = try std.Thread.spawn(.{}, timer_thread_function, .{});
}
