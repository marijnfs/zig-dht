const std = @import("std");
const net = std.net;

const index = @import("index.zig");
const default = index.default;
const connections = index.connections;
const utils = index.utils;

const ID = index.ID;

pub const Server = struct {
    const Config = struct {
        name: []u8 = "",
        port: u16 = 0,
        username: []u8 = "",
    };

    config: Config = .{},
    state: State = .Init,
    stream_server: net.StreamServer,
    id: ID = std.mem.zeroes(ID),
    apparent_address: ?std.net.Address = null,
    incoming_connections: std.AutoHashMap(*connections.InConnection, void),
    outgoing_connections: std.AutoHashMap(*connections.OutConnection, void),

    // router map, mapping message GUIDs to connection GUIDs
    // both for incoming and outgoing connections.
    connection_router: std.AutoHashMap(ID, u64) = undefined,

    pub fn get_incoming_connection(server: *Server, guid: u64) !*connections.InConnection {
        var it = server.incoming_connections.keyIterator();
        while (it.next()) |conn| {
            if (conn.*.guid == guid)
                return conn.*;
        }
        return error.NotFound;
    }

    pub fn get_outgoing_connection(server: *Server, guid: u64) !*connections.OutConnection {
        var it = server.outgoing_connections.keyIterator();
        while (it.next()) |conn| {
            if (conn.*.guid == guid)
                return conn.*;
        }
        return error.NotFound;
    }

    pub fn get_closest_outgoing_connection(server: *Server, id: ID) ?*connections.OutConnection {
        var best_connection: ?*connections.OutConnection = null;
        var lowest_dist = std.mem.zeroes(ID);

        var out_it = server.outgoing_connections.keyIterator();
        while (out_it.next()) |connection| {
            std.log.info("trying to route, looking at connection id:{} addr:{s}", .{ utils.hex(&connection.*.id), connection.*.address });
            if (utils.id_is_zero(connection.*.id))
                continue;

            const dist = utils.xor(connection.*.id, id);
            if (utils.id_is_zero(lowest_dist) or utils.less(dist, lowest_dist)) {
                lowest_dist = dist;
                best_connection = connection.*;
            }
        }
        return best_connection;
    }

    pub fn initialize(server: *Server) !void {
        server.stream_server = net.StreamServer.init(net.StreamServer.Options{ .reuse_address = true });
        server.id = utils.rand_id();
        server.incoming_connections = std.AutoHashMap(*connections.InConnection, void).init(default.allocator);
        server.outgoing_connections = std.AutoHashMap(*connections.OutConnection, void).init(default.allocator);
        server.connection_router = std.AutoHashMap(ID, u64).init(default.allocator);

        std.log.info("Connecting to {s}:{}", .{ server.config.name, server.config.port });
        const localhost = try net.Address.parseIp(server.config.name, server.config.port);
        try server.stream_server.listen(localhost);

        std.log.info("my id: {any}", .{server.id});
    }

    pub fn accept_loop(server: *Server) !void {
        server.state = .Ready;
        errdefer {
            server.state = .Error;
        }
        while (true) {
            var stream_connection = try server.stream_server.accept();

            std.log.info("accepting connection from {}", .{stream_connection});
            var connection = try default.allocator.create(connections.InConnection); //append the frame before assigning to it, it can't move in Memory

            connection.* = .{
                .stream_connection = stream_connection,
                .guid = utils.get_guid(),
            };
            connection.frame = async connection.connection_read_loop();
            try server.incoming_connections.putNoClobber(connection, {});
            //time to schedule event loop to start connection

        }
        @panic("loop ended");
    }

    pub fn connect_and_add(server: *Server, address: net.Address) !*connections.OutConnection {
        errdefer {
            std.log.info("Failed to connect to {}", .{address});
        }
        var out_connection = try default.allocator.create(connections.OutConnection);
        out_connection.* = .{
            .address = address,
            .stream_connection = try net.tcpConnectToAddress(address),
            .guid = utils.get_guid(),
        };
        out_connection.frame = async out_connection.connection_read_loop();
        try server.outgoing_connections.putNoClobber(out_connection, {});
        return out_connection;
    }

    pub fn is_connected_to(server: *Server, address: net.Address) bool {
        var it = server.outgoing_connections.keyIterator();
        while (it.next()) |conn| {
            if (std.net.Address.eql(conn.*.address, address))
                return true;
        }
        return false;
    }

    pub fn clean_incoming_connections(server: *Server) !void {
        var list = std.ArrayList(*connections.InConnection).init(default.allocator);
        defer list.deinit();

        var it = server.incoming_connections.keyIterator();
        while (it.next()) |conn| {
            try list.append(conn.*);
        }

        for (list.items) |conn| {
            if (conn.state == .Disconnected) {
                //todo, Closing the connection might still be needed, but it's not clear what state the stream is in
                // if the stream is not open for writing, closing it causes errors
                // conn.stream_connection.stream.close();
                _ = server.incoming_connections.remove(conn);
            }
        }
    }

    pub fn clean_outgoing_connections(server: *Server) !void {
        var list = std.ArrayList(*connections.OutConnection).init(default.allocator);
        defer list.deinit();

        var it = server.outgoing_connections.keyIterator();
        while (it.next()) |conn| {
            try list.append(conn.*);
        }

        for (list.items) |conn| {
            if (conn.state == .Disconnected) {
                //todo, Closing the connection might still be needed, but it's not clear what state the stream is in
                // if the stream is not open for writing, closing it causes errors
                // conn.stream_connection.close();
                _ = server.outgoing_connections.remove(conn);
            }
        }
    }

    pub fn deinit(server: *Server) void {
        server.stream_server.deinit();
    }

    const State = enum {
        Init,
        Ready,
        Error,
    };
};
