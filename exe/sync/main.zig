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
    const addr = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4040);
    var server = try udp_server.UDPServer.init(addr);
    defer server.deinit();

    // Add default functions
    var timer = try TimerThread.init(server.job_queue);
    try timer.add_timer(10000, timer_functions.expand_connections, true);
    try timer.add_timer(20000, timer_functions.refresh_finger_table, true);
    try timer.add_timer(30000, timer_functions.sync_finger_table, true);

    try server.start();

    try server.wait();
}
