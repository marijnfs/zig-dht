const AtomicQueue = index.AtomicQueue;
const std = @import("std");

const index = @import("index.zig");
const default = index.default;

pub fn JobQueue(comptime Job: type) type {
    return struct {
        queue: AtomicQueue(*Job),

        frame: @Frame(job_loop) = undefined,

        pub fn init() !*@This() {
            var job_queue = try default.allocator.create(@This());
            job_queue.queue = AtomicQueue(*Job).init(default.allocator);
            return job_queue;
        }

        pub fn enqueue(job_queue: *@This(), job: Job) !void {
            const job_ptr = try default.allocator.create(Job);
            job_ptr.* = job;
            std.log.info("queuing job: {}\n", .{job});
            try job_queue.queue.push(job_ptr);
        }

        pub fn start_job_loop(job_queue: *@This()) void {
            job_queue.frame = async job_queue.job_loop();
        }

        pub fn job_loop(job_queue: *@This()) !void {
            while (true) {
                if (job_queue.queue.pop()) |job| {
                    // const stdout = std.io.getStdOut().writer();
                    // nosuspend stdout.print("job: {any}\n", .{job}) catch unreachable;
                    // const data = try std.fmt.allocPrint(default.allocator, "job: {any}\n", .{job});
                    // c.print(data);
                    std.log.info("Work: {}", .{job});
                    job.work(job_queue) catch |e| {
                        std.log.info("Work Error: {}", .{e});
                    };
                    default.allocator.destroy(job);
                } else {
                    //sleep
                    std.time.sleep(10 * std.time.ns_per_ms);
                }
            }
        }
    };
}
