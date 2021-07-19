const std = @import("std");
const net = std.net;

const index = @import("index.zig");

const READ_BUF_SIZE = 1024 * 128; //128 kb

var incoming_connections = std.AutoHashMap(*InConnection, void).init(index.allocator);
var outgoing_connections = std.AutoHashMap(*OutConnection, void).init(index.allocator);

// router map, mapping message GUIDs to connection GUIDs
// both for incoming and outgoing connections.
var connection_router = std.AutoHashMap(u64, u64).init(index.allocator);

pub const InConnection = struct {
    stream_connection: net.StreamServer.Connection,
    state: State = .Connected,
    frame: @Frame(connection_read_loop) = undefined,
    guid: u64 = 0,

    const State = enum {
        Connected,
        Disconnected,
    };

    fn write(connection: *InConnection, buf: []u8) !void {
        try connection.stream_connection.write(buf);
    }

    fn connection_read_loop(connection: *InConnection) !void {
        const stream_connection = connection.stream_connection;
        defer stream_connection.stream.close();
        std.log.info("connection from {}", .{stream_connection.address});
        var buf: [READ_BUF_SIZE]u8 = undefined;

        defer {
            std.log.info("disconnected {}", .{stream_connection});
            connection.state = .Disconnected;
        }

        while (true) {
            var len = try stream_connection.stream.read(&buf);
            std.log.info("read {s}", .{buf[0..len]});
            const guid = index.get_guid();
            try connection_router.put(guid, connection.guid);
            try index.job.enqueue(.{ .message = .{ .guid = guid, .message = try std.mem.dupe(index.allocator, u8, buf[0..len]) } });

            if (len == 0)
                break;
        }
    }
};

pub const OutConnection = struct {
    stream_connection: net.Stream,
    state: State = .Connected,
    frame: @Frame(connection_read_loop) = undefined,
    guid: u64 = 0,
    address: net.Address,

    const State = enum {
        Connected,
        Disconnected,
    };

    fn write(connection: *InConnection, buf: []u8) !void {
        try connection.stream_connection.write(buf);
    }

    fn connection_read_loop(connection: *OutConnection) !void {
        defer connection.stream_connection.close();
        std.log.info("connection to {}", .{connection.address});
        var buf: [READ_BUF_SIZE]u8 = undefined;

        defer {
            std.log.info("stopping connection to {}", .{connection.address});
            connection.state = .Disconnected;
        }

        while (true) {
            var len = try connection.stream_connection.read(&buf);
            std.log.info("read {s}", .{buf[0..len]});
            const guid = index.get_guid();
            try connection_router.put(guid, connection.guid);
            try index.job.enqueue(.{ .message = .{ .guid = guid, .message = try std.mem.dupe(index.allocator, u8, buf[0..len]) } });

            if (len == 0)
                break;
        }
    }
};

pub fn connect_and_add(address: net.Address) !void {
    var out_connection = try index.allocator.create(OutConnection);
    out_connection.* = .{
        .address = address,
        .stream_connection = try net.tcpConnectToAddress(address),
        .guid = index.get_guid(),
    };
    out_connection.frame = async out_connection.connection_read_loop();
    try outgoing_connections.putNoClobber(out_connection, {});
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
            var connection = try index.allocator.create(InConnection); //append the frame before assigning to it, it can't move in Memory
            // TODO, appending to arraylist can actually move other frames if arraylist needs to relocate
            connection.* = .{
                .stream_connection = stream_connection,
                .guid = index.get_guid(),
            };
            connection.frame = async connection.connection_read_loop();
            try incoming_connections.putNoClobber(connection, {});
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
