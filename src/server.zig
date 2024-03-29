const std = @import("std");
const net = std.net;
const time = std.time;

const index = @import("index.zig");
const default = index.default;
const communication = index.communication;
const utils = index.utils;
const serial = index.serial;
const hash = index.hash;
const model = index.model;
const timer = index.timer;
const timer_functions = index.timer_functions;

const Socket = index.Socket;
const Hash = index.Hash;
const ServerJob = index.ServerJob;

const id_ = index.id;
const ID = index.ID;

const JobQueue = index.JobQueue(ServerJob, *Server);

pub const Server = struct {
    const ServerConfig = struct {
        ping_finger_table_timer: i64 = 1000, //time in ms
        sync_finger_table_timer: i64 = 4000,
        search_finger_table_timer: i64 = 5000,
        ping_addresses_seen_timer: i64 = 10000,
        discover_addresses_seen_timer: i64 = 10000,
        public: bool,
    };

    const HookType = fn ([]const u8, ID, net.Address, *Server) anyerror!bool;
    address: net.Address,
    apparent_address: ?net.Address = null,
    socket: *Socket,
    job_queue: *JobQueue,
    id: ID,
    frame: @Frame(accept_loop) = undefined,
    routing: *index.routing.RoutingTable,
    finger_table: *index.finger_table.FingerTable,
    public_finger_table: *index.finger_table.FingerTable, //finger table dedicated to public server

    direct_message_hooks: std.ArrayList(HookType),
    broadcast_hooks: std.ArrayList(HookType),
    public: bool, // Are we on the public internet, and advertise as such (helping with hole punching)

    punch_map: std.AutoHashMap(ID, net.Address),
    timer_thread: *timer.TimerThread,

    pub fn init(address: net.Address, id: ID, config: ServerConfig) !*Server {
        var server = try default.allocator.create(Server);
        server.* = .{
            .address = address,
            .socket = try Socket.init(address),
            .job_queue = try JobQueue.init(server),
            .id = id,
            .routing = try index.routing.RoutingTable.init(id), //record of all ID <> Address pair seen, with some stats
            .finger_table = try index.finger_table.FingerTable.init(id, default.n_fingers), //routing table, to keep in sync
            .public_finger_table = try index.finger_table.FingerTable.init(id, default.n_fingers), //routing table, to keep in sync
            .direct_message_hooks = std.ArrayList(HookType).init(default.allocator),
            .broadcast_hooks = std.ArrayList(HookType).init(default.allocator),
            .punch_map = std.AutoHashMap(ID, net.Address).init(default.allocator),
            .timer_thread = undefined, //defined in init_timer_functions
            .public = config.public,
        };

        try server.init_timer_functions(config);

        return server;
    }

    pub fn deinit(server: *Server) void {
        server.socket.deinit();
        default.allocator.destroy(server);
    }

    pub fn start(server: *Server) !void {
        std.log.info("Starting  Server", .{});

        try server.socket.bind();
        server.address = try server.socket.getAddress();
        server.job_queue.start_job_loop();
        server.frame = async server.accept_loop();
        try server.timer_thread.start();
    }

    pub fn init_timer_functions(server: *Server, config: ServerConfig) !void {
        server.timer_thread = try timer.TimerThread.init(server.job_queue);
        try server.timer_thread.add_timer(config.ping_finger_table_timer, timer_functions.ping_finger_table, true);
        try server.timer_thread.add_timer(config.sync_finger_table_timer, timer_functions.sync_finger_table_with_routing, true);
        try server.timer_thread.add_timer(config.search_finger_table_timer, timer_functions.search_finger_table, true);
        try server.timer_thread.add_timer(config.ping_addresses_seen_timer, timer_functions.ping_addresses_seen, true);
        try server.timer_thread.add_timer(config.discover_addresses_seen_timer, timer_functions.discover_addresses_seen, true);
    }

    pub fn wait(server: *Server) !void {
        try await server.frame;
    }

    pub fn add_broadcast_hook(server: *Server, hook: HookType) !void {
        try server.broadcast_hooks.append(hook);
    }

    pub fn add_direct_message_hook(server: *Server, hook: HookType) !void {
        try server.direct_message_hooks.append(hook);
    }

    fn accept_loop(server: *Server) !void {
        while (true) {
            const msg = try server.socket.recvFrom();

            try server.routing.add_address_seen(msg.from);

            // Update / Add record
            if (!try server.routing.verify_address(msg.from)) {
                continue;
            }

            try server.job_queue.enqueue(.{ .inbound_message = msg });
        }
    }

    pub fn queue_direct_message(server: *Server, id: ID, buf: []const u8) !void {
        try communication.enqueue_envelope(.{ .direct_message = buf }, .{ .id = id }, server);
    }

    pub fn queue_broadcast(server: *Server, buf: []const u8) !void {
        std.log.debug("queue_broadcast", .{});
        const envelope = communication.build_envelope(.{ .broadcast = buf }, .{ .id = std.mem.zeroes(ID) }, server);
        try server.job_queue.enqueue(.{ .broadcast = envelope });
    }

    pub fn send(server: *Server, id: ID, buf: []const u8) !void {
        if (server.id_index.get(id)) |record| {
            server.socket.sendTo(record.address, buf);
        } else {
            return error.IDNotInRecords;
        }
    }
};

test "Simple Server Test" {
    const addr = net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 4040);
    var server = try Server.init(addr);
    defer server.deinit();

    // server.start();
    // server.stop();
}
