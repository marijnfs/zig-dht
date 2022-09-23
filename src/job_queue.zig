const AtomicQueue = index.AtomicQueue;
const std = @import("std");

const index = @import("index.zig");
const default = index.default;

pub fn JobQueue(comptime Job: type, comptime Context: type) type {
    return struct {
        queue: AtomicQueue(*Job),

        frame: @Frame(job_loop) = undefined,
        context: Context,

        pub fn init(context: Context) !*@This() {
            var job_queue = try default.allocator.create(@This());
            job_queue.* = .{
                .queue = AtomicQueue(*Job).init(default.allocator),
                .context = context,
            };
            return job_queue;
        }

        pub fn enqueue(job_queue: *@This(), job: Job) !void {
            const job_ptr = try default.allocator.create(Job);
            job_ptr.* = job;

            try job_queue.queue.push(job_ptr);
        }

        pub fn start_job_loop(job_queue: *@This()) void {
            job_queue.frame = async job_queue.job_loop();
        }

        pub fn job_loop(job_queue: *@This()) !void {
            while (true) {
                if (job_queue.queue.pop()) |job| {
                    // nosuspend {
                    // std.log.debug("Work: {s}", .{@tagName(job)});
                    job.work(job_queue, job_queue.context) catch |e| {
                        std.log.warn("Work Error: {}", .{e});
                    };
                    default.allocator.destroy(job);
                    // }
                } else {
                    //sleep
                    std.time.sleep(1 * std.time.ns_per_ms);
                }
            }
        }
    };
}
