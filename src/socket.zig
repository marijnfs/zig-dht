const std = @import("std");
const net = std.net;
const os = std.os;

const index = @import("index.zig");
const default = index.default;
const READ_BUF = 64 << 20;

pub const UDPIncoming = struct {
    buf: []const u8,
    from: net.Address,
};

pub const UDPSocket = struct {
    fd: os.socket_t,
    address: net.Address,

    pub fn init(address: net.Address) !*UDPSocket {
        var socket = try default.allocator.create(UDPSocket);

        const sock_flags = os.SOCK.DGRAM | os.SOCK.CLOEXEC | os.SOCK.NONBLOCK;

        socket.* = .{
            .fd = try os.socket(address.any.family, sock_flags, os.IPPROTO.UDP),
            .address = address,
        };

        return socket;
    }

    pub fn deinit(socket: *UDPSocket) void {
        os.closeSocket(socket.fd);
        default.allocator.destroy(socket);
    }

    pub fn bind(socket: *UDPSocket) !void {
        try os.bind(socket.fd, &socket.address.any, socket.address.getOsSockLen());
    }

    pub fn sendTo(socket: *UDPSocket, address: net.Address, buf: []const u8) !void {
        if (std.io.is_async) {
            _ = try std.event.Loop.instance.?.sendto(socket.fd, buf, os.MSG.NOSIGNAL, &address.any, address.getOsSockLen());
        } else {
            _ = try os.sendto(socket.fd, buf, os.MSG.NOSIGNAL, &address.any, address.getOsSockLen());
        }
    }

    pub fn recvFrom(socket: *UDPSocket) !UDPIncoming {
        var flags: u32 = 0;
        var src_sockaddr: os.sockaddr = undefined;
        var addrlen: os.socklen_t = @sizeOf(os.sockaddr);

        var buf = try default.allocator.alloc(u8, READ_BUF);
        defer default.allocator.free(buf);
        const rlen = if (std.io.is_async)
            try std.event.Loop.instance.?.recvfrom(socket.fd, buf, flags, &src_sockaddr, &addrlen)
        else
            try os.recvfrom(socket.fd, buf, flags, &src_sockaddr, &addrlen);

        // std.log.info("rlen {}", .{rlen});
        const src_address = net.Address{ .any = src_sockaddr };
        // const src_address: net.Address = socket.address;
        return UDPIncoming{ .buf = try default.allocator.dupe(u8, buf[0..rlen]), .from = src_address };
    }

    pub fn getAddress(socket: *UDPSocket) !net.Address {
        var addr: os.sockaddr = undefined;
        var addrlen: os.socklen_t = @sizeOf(os.sockaddr);
        try os.getsockname(socket.fd, &addr, &addrlen);
        return net.Address{ .any = addr };
    }
};

test "just init" {
    const addr = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4040);
    var socket = try UDPSocket.init(addr);
    defer socket.deinit();
    try socket.bind();

    const other_addr = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4041);
    var other_socket = try UDPSocket.init(other_addr);
    try other_socket.bind();
    defer other_socket.deinit();

    var buf: []const u8 = "blaa";
    try socket.sendTo(other_addr, buf);

    var recv = try other_socket.recvFrom();
    std.log.warn("{}", .{recv});

    std.log.warn("addr: {}", .{try socket.getAddress()});
    std.log.warn("{}", .{try other_socket.getAddress()});
}
