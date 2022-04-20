const std = @import("std");
const net = std.net;

const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;
const utils = index.utils;

const ID = index.ID;

const READ_BUF_SIZE = 1024 * 128; //128 kb

pub const Connection = struct {
    stream: net.Stream = undefined,
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

    pub fn connect(connection: *Connection) !void {
        connection.state = .Disconnected;
        errdefer {
            connection.state = .Error;
        }
        connection.stream = try net.tcpConnectToAddress(connection.address);
        connection.start_read_loop();
        connection.state = .Connected;
    }

    pub fn write(connection: *Connection, buf: []u8) !void {
        std.log.info("write n:{}", .{buf.len});

        errdefer connection.state = .Disconnected;
        const len = try connection.stream.write(buf);
        if (len != buf.len)
            return error.WriteError;
    }

    pub fn start_read_loop(connection: *Connection) void {
        connection.frame = async connection.connection_read_loop();
    }

    pub fn close(connection: *Connection) void {
        connection.stream.close();
    }

    pub fn connection_read_loop(connection: *Connection) !void {
        std.log.info("starting read on {}", .{connection.address});
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
            var len = try connection.stream.read(&buf);
            std.log.info("read incoming backward len:{} ", .{buf.len});

            try jobs.enqueue(.{ .inbound_message = .{ .guid = connection.guid, .content = try default.allocator.dupe(u8, buf[0..len]) } });

            if (len == 0) {
                std.log.info("read 0 bytes, stopping {}", .{connection.address});
                break;
            }
        }
        connection.close();
    }

    pub fn format(
        self: *Connection,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Conn[{}] = {s}", .{ utils.hex(self.id), self.address });
    }
};
