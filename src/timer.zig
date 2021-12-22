const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;

const Timer = struct { alarm: i64 = 0, callback: fn () anyerror!void, delay: i64 = 0 };

fn compare_timer(_: void, t1: Timer, t2: Timer) std.math.Order {
    if (t1.alarm < t2.alarm) return .lt else return .gt;
}

var queue = std.PriorityQueue(Timer, void, compare_timer).init(default.allocator, .{});

// var timer_thread: std.Thread = undefined;
var timer_frame: @Frame(timer_thread_function) = undefined;

pub fn add_timer(delay: i64, callback: fn () anyerror!void, repeat: bool) !void {
    try queue.add(Timer{ .alarm = std.time.milliTimestamp() + delay, .delay = if (repeat) delay else 0, .callback = callback });
}

pub fn timer_thread_function() !void {
    while (true) {
        if (queue.peek()) |timer_| {
            // std.log.info("time {} {}", .{ std.time.milliTimestamp(), timer_ });
            if (std.time.milliTimestamp() > timer_.alarm) {
                try jobs.enqueue(.{ .callback = timer_.callback });
                if (timer_.delay > 0) {
                    var new_timer = timer_;
                    new_timer.alarm += timer_.delay;
                    try queue.add(new_timer);
                }

                _ = queue.remove();
            } else {
                std.time.sleep(100 * std.time.ns_per_ms); // short sleep, we could sleep until next alarm, but other alarms could be introduced in the mean time
            }
        } else {
            std.time.sleep(100 * std.time.ns_per_ms); // short sleep
        }
    }
}

pub fn start_timer_thread() !void {
    // timer_thread = try std.Thread.spawn(.{}, timer_thread_function, .{});
    timer_frame = async timer_thread_function();
}
