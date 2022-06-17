const std = @import("std");
const net = std.net;
const time = std.time;

const index = @import("index.zig");
const default = index.default;
const communication = index.communication_udp;
const utils = index.utils;
const serial = index.serial;
const hash = index.hash;
const model = index.model;

const UDPSocket = index.UDPSocket;
const Hash = index.Hash;
const ServerJob = index.ServerJob;

const id_ = index.id;
const ID = index.ID;

const JobQueue = index.JobQueue(ServerJob, *UDPServer);

pub const UDPServer = struct {
    const HookType = fn ([]const u8, ID, net.Address) anyerror!void;
    address: net.Address,
    apparent_address: ?net.Address = null,
    socket: *UDPSocket,
    job_queue: *JobQueue,
    id: ID,
    frame: @Frame(accept_loop) = undefined,
    routing: *index.routing.RoutingTable,
    finger_table: *index.finger_table.FingerTable,

    direct_message_hooks: std.ArrayList(HookType),
    broadcast_hooks: std.ArrayList(HookType),
    public: bool = false, // Are we on the public internet, and advertise as such (helping with hole punching)

    punch_map: std.AutoHashMap(ID, net.Address),

    pub fn init(address: net.Address, id: ID) !*UDPServer {
        var server = try default.allocator.create(UDPServer);
        server.* = .{
            .address = address,
            .socket = try UDPSocket.init(address),
            .job_queue = try JobQueue.init(server),
            .id = id,
            .routing = try index.routing.RoutingTable.init(id), //record of all ID <> Address pair seen, with some stats
            .finger_table = try index.finger_table.FingerTable.init(id, default.n_fingers), //routing table, to keep in sync

            .direct_message_hooks = std.ArrayList(HookType).init(default.allocator),
            .broadcast_hooks = std.ArrayList(HookType).init(default.allocator),
            .punch_map = std.AutoHashMap(ID, net.Address).init(default.allocator),
        };
        return server;
    }

    pub fn deinit(server: *UDPServer) void {
        server.socket.deinit();
        default.allocator.destroy(server);
    }

    pub fn start(server: *UDPServer) !void {
        std.log.info("Starting UDP Server", .{});

        try server.socket.bind();
        server.address = try server.socket.getAddress();
        server.job_queue.start_job_loop();
        server.frame = async server.accept_loop();
    }

    pub fn wait(server: *UDPServer) !void {
        try await server.frame;
    }

    pub fn add_broadcast_hook(server: *UDPServer, hook: HookType) !void {
        try server.broadcast_hooks.append(hook);
    }

    pub fn add_direct_message_hook(server: *UDPServer, hook: HookType) !void {
        try server.direct_message_hooks.append(hook);
    }

    fn accept_loop(server: *UDPServer) !void {
        while (true) {
            std.log.info("Getting", .{});
            const msg = try server.socket.recvFrom();
            std.log.info("got msg:{s}", .{index.hex(msg.buf)});

            try server.routing.add_address_seen(msg.from);

            // Update / Add record
            if (!try server.routing.verify_address(msg.from)) {
                continue;
            }

            try server.job_queue.enqueue(.{ .inbound_message = msg });
        }
    }

    pub fn queue_direct(server: *UDPServer, id: ID, buf: []const u8) !void {
        communication.enqueue_envelope(.{ .direct_message = buf }, .{ .id = id }, server);
    }

    pub fn queue_broadcast(server: *UDPServer, buf: []const u8) !void {
        var it = server.finger_table.valueIterator();
        while (it.next()) |f| {
            try communication.enqueue_envelope(.{ .direct_message = buf }, .{ .id = f.id }, server);
        }
    }

    pub fn send(server: *UDPServer, id: ID, buf: []const u8) !void {
        if (server.id_index.get(id)) |record| {
            server.socket.sendTo(record.address, buf);
        } else {
            return error.IDNotInRecords;
        }
    }
};

test "Simple Server Test" {
    const addr = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4040);
    var server = try UDPServer.init(addr);
    defer server.deinit();

    // server.start();
    // server.stop();
}
