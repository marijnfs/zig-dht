pub const io_mode = .evented; // use event loop

const std = @import("std");
const net = std.net;
const dht = @import("dht");
const default = dht.default;
const udp_server = dht.udp_server;
const socket = dht.socket;
const timer_functions = dht.timer_functions;

const TimerThread = dht.timer.TimerThread;

pub fn main() !void {
    var args = try std.process.argsAlloc(default.allocator);
    defer std.process.argsFree(default.allocator, args);
    std.log.info("arg0 {s}", .{args[0]});

    try dht.init();

    const server_port = try std.fmt.parseInt(u16, args[2], 0);
    const server_address = try std.net.Address.parseIp(args[1], server_port);

    // const addr = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4040);
    const id = dht.id.rand_id();
    var server = try udp_server.UDPServer.init(server_address, id);
    defer server.deinit();

    // add initial connection
    if (args.len >= 5) {
        const port = try std.fmt.parseInt(u16, args[4], 0);
        const address = try std.net.Address.parseIp(args[3], port);
        try server.routing.add_address_seen(address);
        try server.job_queue.enqueue(.{ .connect = address });
    }

    // Add default functions
    var timer_thread = try TimerThread.init(server.job_queue);
    try timer_thread.add_timer(10000, timer_functions.expand_connections, true);
    try timer_thread.add_timer(20000, timer_functions.refresh_finger_table, true);
    try timer_thread.add_timer(30000, timer_functions.sync_finger_table, true);
    try timer_thread.start();

    try server.start();

    try server.wait();
}
