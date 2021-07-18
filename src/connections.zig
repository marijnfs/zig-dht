const std = @import("std");
const net = std.net;

const index = @import("index.zig");

var incomming_connections = std.AutoHashMap(*Connection, void).init(index.allocator);

pub const Connection = struct {
    stream_connection: net.StreamServer.Connection,
    state: State = .Connected,
    frame: @Frame(connection_read_loop),

    const State = enum {
        Connected,
        Disconnected,
    };
};

fn connection_read_loop(connection: net.StreamServer.Connection) !void {
    defer connection.stream.close();
    std.log.info("connection from {}", .{connection});
    var buf: [100]u8 = undefined;

    defer {
        std.log.info("disconnected {}", .{connection});
    }

    while (true) {
        var frame = connection.stream.read(&buf);
        var len = try frame;
        // const len = try connection.stream.read(&buf);
        std.log.info("read {s}", .{buf[0..len]});
        try index.job.enqueue(.{ .message = try std.mem.dupe(index.allocator, u8, buf[0..len]) });

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
        std.log.info("Connecting to {s}:{}", .{ server.config.name, server.config.port });
        const localhost = try net.Address.parseIp(server.config.name, server.config.port);
        try server.stream_server.listen(localhost);
    }

    pub fn accept_loop(server: *Server) !void {
        while (true) {
            var stream_connection = try server.stream_server.accept();
            var connection = try index.allocator.create(Connection); //append the frame before assigning to it, it can't move in Memory
            // TODO, appending to arraylist can actually move other frames if arraylist needs to relocate
            connection.stream_connection = stream_connection;
            connection.frame = async connection_read_loop(stream_connection);
            try incomming_connections.putNoClobber(connection, {});
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
        Error,
    };
};
