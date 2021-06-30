example.zig

const std = @import("std");
const net = std.net;

pub const io_mode = .evented;

fn testClient(addr: net.Address) anyerror!void {
    const socket_file = try net.tcpConnectToAddress(addr);
    defer socket_file.close();

    var buf: [100]u8 = undefined;
    const len = try socket_file.read(&buf);
    const msg = buf[0..len];
    std.log.info("client read: {s}", .{msg});

    var out_buf = "Hey back";
    const written = try socket_file.write(out_buf);
}

fn testServerReader(reader: net.Stream.Reader) anyerror!void {
    var buf: [100]u8 = undefined;
    const len = try reader.read(&buf);
    std.log.info("Server got {s}", .{buf[0..len]});
}

fn testServerWriter(writer: net.Stream.Writer) anyerror!void {
    try writer.print("hello from server\n", .{});
}

fn testServer(server: *net.StreamServer) anyerror!void {
    var client = try server.accept();

    const writer = client.stream.writer();
    var writer_frame = async testServerWriter(writer);

    const reader = client.stream.reader();
    var reader_frame = async testServerReader(reader);

    try await writer_frame;
    try await reader_frame;
}

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});

    const localhost = try net.Address.parseIp("127.0.0.1", 4141);

    std.log.info("Addr {}.", .{localhost});

    var server = net.StreamServer.init(net.StreamServer.Options{});
    defer server.deinit();
    try server.listen(localhost);

    std.log.info("Listen address {}", .{server.listen_address});
    var server_frame = async testServer(&server);
    var client_frame = async testClient(server.listen_address);

    try await client_frame;
    try await server_frame;
}
