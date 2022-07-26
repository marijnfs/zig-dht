pub const io_mode = .evented; // use event loop
// pub const log_level: std.log.Level = .info;

const args = @import("args");
const std = @import("std");
const net = std.net;
const dht = @import("dht");
const default = dht.default;
const socket = dht.socket;
const timer_functions = dht.timer_functions;

const TimerThread = dht.timer.TimerThread;

const Messages = union(enum) {
    check_state: dht.Hash,
    bloom_check: struct {
        filter: []bool,
    },
};

fn direct_message_hook(buf: []const u8, src_id: dht.ID, src_address: net.Address) !void {
    std.log.info("direct message hook {} {} {}", .{ dht.hex(buf), dht.hex(&src_id), src_address });
}

fn broadcast_hook(buf: []const u8, src_id: dht.ID, src_address: net.Address) !void {
    std.log.info("broadcast hook {s} {} {}", .{ buf, dht.hex(&src_id), src_address });
}

pub fn main() !void {
    const options = try args.parseForCurrentProcess(struct {
        ip: ?[]const u8,
        port: ?u16,
        remote_ip: ?[]const u8 = null,
        remote_port: ?u16 = null,
    }, std.heap.page_allocator, .print);
    if (options.options.ip == null or options.options.port == null) {
        std.log.warn("Ip not defined", .{});
        return;
    }
    try dht.init();

    const address = try std.net.Address.parseIp(options.options.ip.?, options.options.port.?);
    const id = dht.id.rand_id();
    var server = try dht.server.Server.init(address, id);
    defer server.deinit();

    if (options.options.remote_ip != null and options.options.remote_port != null) {
        const address_remote = try std.net.Address.parseIp(options.options.remote_ip.?, options.options.remote_port.?);
        try server.routing.add_address_seen(address_remote);
        try server.job_queue.enqueue(.{ .connect = address_remote });
    }

    try server.add_direct_message_hook(direct_message_hook);
    try server.add_broadcast_hook(broadcast_hook);

    // add initial connection
    // if (args.len >= 5) {
    //     const port = try std.fmt.parseInt(u16, args[4], 0);
    //     const address = try std.net.Address.parseIp(args[3], port);
    //     try server.routing.add_address_seen(address);
    //     try server.job_queue.enqueue(.{ .connect = address });
    // }

    // Add default functions

    var timer_thread = try TimerThread.init(server.job_queue);
    try timer_thread.add_timer(1000, timer_functions.ping_finger_table, true);
    try timer_thread.add_timer(4000, timer_functions.sync_finger_table_with_routing, true);
    try timer_thread.add_timer(5000, timer_functions.search_finger_table, true);
    try timer_thread.add_timer(10000, timer_functions.bootstrap_connect_seen, true);

    try timer_thread.start();

    try server.start();

    while (true) {
        std.log.info("Queueing Hello", .{});
        try server.queue_broadcast("hello");
        std.time.sleep(std.time.ns_per_s);
    }
    try server.wait();
}
