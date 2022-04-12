const std = @import("std");
const net = std.net;

const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;
const utils = index.utils;

const ID = index.ID;

const READ_BUF_SIZE = 1024 * 128; //128 kb

// pub fn route_hash(hash: ID) ?u64 {
//     return connection_router.get(hash);
// }

pub const InConnection = struct {
    stream_connection: net.StreamServer.Connection,
    state: State = .Connected,
    frame: @Frame(connection_read_loop) = undefined,
    guid: u64 = 0,
    id: ID = std.mem.zeroes(ID),

    const State = enum {
        Connected,
        Disconnected,
    };

    pub fn address(conn: *InConnection) std.net.Address {
        return conn.stream_connection.address;
    }

    pub fn write(connection: *InConnection, buf: []u8) !void {
        std.log.info("write n:{}", .{buf.len});
        const len = try connection.stream_connection.stream.write(buf);
        if (len != buf.len)
            return error.WriteError;
    }

    pub fn start(connection: *InConnection) void {
        connection.frame = async connection.connection_read_loop();
    }

    pub fn connection_read_loop(connection: *InConnection) !void {
        const stream_connection = connection.stream_connection;
        std.log.info("connection from {}", .{stream_connection.address});
        var buf: [READ_BUF_SIZE]u8 = undefined;

        defer {
            std.log.info("disconnected {}", .{stream_connection});
            connection.state = .Disconnected;
        }

        while (true) {
            var len = try stream_connection.stream.read(&buf);
            try jobs.enqueue(.{ .inbound_forward_message = .{ .guid = connection.guid, .content = try default.allocator.dupe(u8, buf[0..len]) } });

            if (len == 0)
                break;
        }

        defer stream_connection.stream.close();
    }
};

pub const OutConnection = struct {
    stream_connection: net.Stream = undefined,
    state: State = .Disconnected,
    frame: @Frame(connection_read_loop) = undefined,
    guid: u64 = 0,
    address: net.Address,
    id: ID = std.mem.zeroes(ID),

    const State = enum {
        Connected,
        Disconnected,
        Error,
    };

    pub fn connect(connection: *OutConnection) !void {
        connection.state = .Disconnected;
        errdefer {
            connection.state = .Error;
        }
        connection.stream_connection = try net.tcpConnectToAddress(connection.address);
        connection.frame = async connection.connection_read_loop();
        connection.state = .Connected;
    }

    pub fn write(connection: *OutConnection, buf: []u8) !void {
        std.log.info("write n:{}", .{buf.len});

        errdefer connection.state = .Disconnected;
        const len = try connection.stream_connection.write(buf);
        if (len != buf.len)
            return error.WriteError;
    }

    pub fn start(connection: *OutConnection) void {
        connection.frame = async connection.connection_read_loop();
    }

    pub fn close(connection: *OutConnection) void {
        connection.stream_connection.close();
    }

    pub fn connection_read_loop(connection: *OutConnection) !void {
        std.log.info("connection to {}", .{connection.address});
        var buf: [READ_BUF_SIZE]u8 = undefined;

        errdefer {
            std.log.info("connection to {} failed", .{connection.address});
            connection.state = .Error;
        }
        defer {
            std.log.info("stopping connection to {}", .{connection.address});
            connection.state = .Disconnected;
        }

        while (true) {
            var len = try connection.stream_connection.read(&buf);
            std.log.info("read incoming backward len:{} ", .{buf.len});

            try jobs.enqueue(.{ .inbound_backward_message = .{ .guid = connection.guid, .content = try default.allocator.dupe(u8, buf[0..len]) } });

            if (len == 0)
                break;
        }
        connection.close();
    }

    pub fn format(
        self: *OutConnection,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Conn[{}] = {s}", .{ utils.hex(self.id), self.address });
    }
};
