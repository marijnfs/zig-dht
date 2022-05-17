pub const io_mode = .evented; // use event loop

const std = @import("std");
const net = std.net;
const dht = @import("dht");
const default = dht.default;
const udp_server = dht.udp_server;
const socket = dht.socket;

pub fn main() !void {
    var args = try std.process.argsAlloc(default.allocator);
    defer std.process.argsFree(default.allocator, args);
    std.log.info("arg0 {s}", .{args[0]});

    try dht.init();
    const addr = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4040);
    var server = try udp_server.UDPServer.init(addr);
    defer server.deinit();

    try server.start();

    const sock_address = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4041);
    const sock = try socket.UDPSocket.init(sock_address);
    try sock.bind();

    std.time.sleep(std.time.ns_per_s);
    std.log.info("sending", .{});
    try sock.sendTo(addr, "bla");

    try server.wait();
}
