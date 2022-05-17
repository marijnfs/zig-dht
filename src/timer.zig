const std = @import("std");

const index = @import("index.zig");
const default = index.default;

const ServerJob = index.server_job.ServerJob;
const UDPServer = index.UDPServer;
const Timer = struct { alarm: i64 = 0, callback: fn (*UDPServer) anyerror!void, delay: i64 = 0 };

fn compare_timer(_: void, t1: Timer, t2: Timer) std.math.Order {
    if (t1.alarm < t2.alarm) return .lt else return .gt;
}

pub const TimerThread = struct {
    queue: std.PriorityQueue(Timer, void, compare_timer),

    // var timer_thread: std.Thread = undefined;
    timer_frame: @Frame(timer_thread_function) = undefined,
    work_queue: *index.JobQueue(ServerJob, *index.UDPServer),

    pub fn init(work_queue: *index.JobQueue(ServerJob, *index.UDPServer)) !*TimerThread {
        var timer_thread = try default.allocator.create(TimerThread);
        timer_thread.* = .{
            .queue = std.PriorityQueue(Timer, void, compare_timer).init(default.allocator, .{}),
            .work_queue = work_queue,
        };
        return timer_thread;
    }

    pub fn add_timer(timer_thread: *TimerThread, delay: i64, callback: fn (*UDPServer) anyerror!void, repeat: bool) !void {
        try timer_thread.queue.add(Timer{ .alarm = std.time.milliTimestamp() + delay, .delay = if (repeat) delay else 0, .callback = callback });
    }

    pub fn timer_thread_function(timer_thread: *TimerThread) !void {
        while (true) {
            if (timer_thread.queue.peek()) |timer_| {
                // std.log.info("time {} {}", .{ std.time.milliTimestamp(), timer_ });
                if (std.time.milliTimestamp() > timer_.alarm) {
                    try timer_thread.work_queue.enqueue(.{ .callback = timer_.callback });
                    if (timer_.delay > 0) {
                        var new_timer = timer_;
                        new_timer.alarm += timer_.delay;
                        try timer_thread.queue.add(new_timer);
                    }

                    _ = timer_thread.queue.remove();
                } else {
                    std.time.sleep(100 * std.time.ns_per_ms); // short sleep, we could sleep until next alarm, but other alarms could be introduced in the mean time
                }
            } else {
                std.time.sleep(100 * std.time.ns_per_ms); // short sleep
            }
        }
    }

    pub fn start(timer_thread: *TimerThread) !void {
        // timer_thread = try std.Thread.spawn(.{}, timer_thread_function, .{});
        timer_thread.timer_frame = async timer_thread.timer_thread_function();
    }
};
