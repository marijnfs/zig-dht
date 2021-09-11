const std = @import("std");
const net = std.net;

const index = @import("index.zig");
const default = index.default;
const connections = index.connections;
const utils = index.utils;

const ID = index.ID;

pub const Server = struct {
    const Config = struct {
        name: []u8 = undefined,
        port: u16 = 0,
    };

    config: Config,
    state: State = .Init,
    stream_server: net.StreamServer = undefined,
    id: ID = std.mem.zeroes(ID),

    incoming_connections: std.AutoHashMap(*connections.InConnection, void) = undefined,
    outgoing_connections: std.AutoHashMap(*connections.OutConnection, void) = undefined,

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

    pub fn initialize(server: *Server) !void {
        server.stream_server = net.StreamServer.init(net.StreamServer.Options{});
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
            var connection = try default.allocator.create(connections.InConnection); //append the frame before assigning to it, it can't move in Memory

            connection.* = .{
                .stream_connection = stream_connection,
                .guid = utils.get_guid(),
            };
            connection.frame = async connection.connection_read_loop();
            try server.incoming_connections.putNoClobber(connection, {});
            //time to schedule event loop to start connection

        }
    }

    pub fn connect_and_add(server: *Server, address: net.Address) !*connections.OutConnection {
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

    pub fn deinit(server: *Server) void {
        server.stream_server.deinit();
    }

    const State = enum {
        Init,
        Ready,
        Error,
    };
};
