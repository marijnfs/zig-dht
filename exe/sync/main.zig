pub const io_mode = .evented; // use event loop

const args = @import("args");
const std = @import("std");
const net = std.net;
const dht = @import("dht");
const default = dht.default;
const udp_server = dht.udp_server;
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
    std.log.info("direct message {} {} {}", .{ dht.hex(buf), dht.hex(&src_id), src_address });
}

fn broadcast_hook(buf: []const u8, src_id: dht.ID, src_address: net.Address) !void {
    std.log.info("direct message {} {} {}", .{ dht.hex(buf), dht.hex(&src_id), src_address });
}

pub fn main() !void {
    const options = try args.parseForCurrentProcess(struct {
        ip: ?[]const u8,
        port: ?u16,
        ip_remote: ?[]const u8 = null,
        port_remote: ?u16 = null,
    }, std.heap.page_allocator, .print);
    if (options.options.ip == null or options.options.port == null) {
        std.log.warn("Ip not defined", .{});
        return;
    }
    try dht.init();

    const address = try std.net.Address.parseIp(options.options.ip.?, options.options.port.?);
    const id = dht.id.rand_id();
    var server = try udp_server.UDPServer.init(address, id);
    defer server.deinit();

    if (options.options.ip_remote != null and options.options.port_remote != null) {
        const address_remote = try std.net.Address.parseIp(options.options.ip_remote.?, options.options.port_remote.?);
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
    try timer_thread.add_timer(10000, timer_functions.expand_connections, true);
    try timer_thread.add_timer(20000, timer_functions.refresh_finger_table, true);
    try timer_thread.add_timer(30000, timer_functions.sync_finger_table, true);
    try timer_thread.start();

    try server.start();

    while (true) {
        try server.queue_broadcast("hello");
        std.time.sleep(std.time.ns_per_s);
    }
    try server.wait();
}
