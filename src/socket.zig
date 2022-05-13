const std = @import("std");
const net = std.net;
const os = std.os;

const index = @import("index.zig");
const default = index.default;
const READ_BUF = 64<<20;
const UDPSocket = struct {
    fd: os.socket_t,

    pub fn init(address: net.Address) !*UDPSocket {
        var socket = try default.allocator.create(UDPSocket);
        const sock_flags = os.SOCK.DGRAM | os.SOCK.CLOEXEC;
        socket.fd = try os.socket(address.any.family, sock_flags, os.IPPROTO.UDP);
        return socket;
    }

    pub fn deinit(socket: *UDPSocket) void {
        os.closeSocket(socket.fd);
    }

    pub fn sendTo(socket: *UDPSocket, address: net.Address, buf: []const u8) !void {
        if (std.io.is_async) {
            _ = try std.event.Loop.instance.?.sendto(socket.fd, buf, os.MSG.NOSIGNAL, &address.any, address.getOsSockLen());
        } else {
            _ = try os.sendto(socket.fd, buf, os.MSG.NOSIGNAL, &address.any, address.getOsSockLen());
        }
    }
    pub fn recvFrom(socket: *UDPSocket, address: net.Address, buf: []const u8) !void {
    var flags: u32 = 0;
    var src_addr: ?*sockaddr = undefined;
    var addrlen: ?*socklen_t = undefined;
    var buf: [READ_BUF]u8 = undefined;
                const rlen = if (std.io.is_async)
                try std.event.Loop.instance.?.recvfrom(socket.fd, buf, flags, &sa.any, &sl_copy) catch break
            else
                try os.recvfrom(fd, answer_bufs[next], 0, &sa.any, &sl_copy) catch break;

};

test "just init" {
    const addr = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4040);
    var socket = try UDPSocket.init(addr);
    defer socket.deinit();
}
