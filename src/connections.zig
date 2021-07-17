const std = @import("std");
const net = std.net;

const index = @import("index.zig");

var incomming_connections = std.ArrayList(net.StreamServer.Connection).init(index.allocator);
var incomming_connection_frames = std.ArrayList(@Frame(connection_read_loop)).init(index.allocator);

fn connection_read_loop(connection: net.StreamServer.Connection) !void {
    defer connection.stream.close();
    std.log.info("connection from {}", .{connection});
    var buf: [100]u8 = undefined;

    while (true) {
        var frame = connection.stream.read(&buf);
        var len = try frame;
        // const len = try connection.stream.read(&buf);
        std.log.info("read {s}", .{buf[0..len]});
        if (len == 0)
            break;
    }
}

pub const Server = struct {
    config: Config,
    state: State = .Init,
    stream_server: net.StreamServer = undefined,

    pub fn initialize(server: *Server) !void {
        server.stream_server = net.StreamServer.init(net.StreamServer.Options{});
        const localhost = try net.Address.parseIp(server.config.name, server.config.port);
        try server.stream_server.listen(localhost);
    }

    pub fn accept_loop(server: *Server) !void {
        while (true) {
            var connection = try server.stream_server.accept();

            try incomming_connections.append(connection);
            var frame: @Frame(connection_read_loop) = undefined;
            try incomming_connection_frames.append(frame);
            incomming_connection_frames.items[incomming_connection_frames.items.len - 1] = async connection_read_loop(connection);

            //time to schedule event loop to start connection

        }
    }

    pub fn deinit(server: *Server) void {
        server.stream_server.deinit();
    }

    const Config = struct {
        name: []u8,
        port: u16,
    };

    const State = enum {
        Init,
        Ready,
        Done,
        Error,
    };
};
