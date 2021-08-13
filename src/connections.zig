const std = @import("std");
const net = std.net;

usingnamespace @import("index.zig");

const READ_BUF_SIZE = 1024 * 128; //128 kb

pub fn route_hash(hash: ID) ?u64 {
    return connection_router.get(hash);
}

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

    pub fn write(connection: *InConnection, buf: []u8) !void {
        const len = try connection.stream_connection.stream.write(buf);
        if (len != buf.len)
            return error.WriteError;
    }

    pub fn connection_read_loop(connection: *InConnection) !void {
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
            const hash = utils.calculate_hash(buf[0..len]);
            try default.server.connection_router.put(hash, connection.guid);
            try jobs.enqueue(.{ .process_message = .{ .hash = hash, .data = try std.mem.dupe(default.allocator, u8, buf[0..len]) } });

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
    id: ID = std.mem.zeroes(ID),

    const State = enum {
        Connected,
        Disconnected,
    };

    pub fn write(connection: *OutConnection, buf: []u8) !void {
        const len = try connection.stream_connection.write(buf);
        if (len != buf.len)
            return error.WriteError;
    }

    pub fn connection_read_loop(connection: *OutConnection) !void {
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
            const hash = utils.calculate_hash(buf[0..len]);
            try default.server.connection_router.put(hash, connection.guid);
            try jobs.enqueue(.{ .process_message = .{ .hash = hash, .data = try std.mem.dupe(default.allocator, u8, buf[0..len]) } });

            if (len == 0)
                break;
        }
    }
};
