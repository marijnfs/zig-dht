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
    const Record = struct {
        address: net.Address = undefined,
        id: ID = std.mem.zeroes(ID),
        red_flags: usize = 0,
        last_connect: i64 = 0,
    };
    const HookType = fn ([]const u8, ID, net.Address) anyerror!void;

    records: std.ArrayList(*Record),
    ip_index: std.StringHashMap(*Record),
    id_index: std.AutoHashMap(ID, *Record),
    address: net.Address,
    apparent_address: ?net.Address = null,
    public: bool = false, //Are we a public IP (is apparent address same a ours)
    socket: *UDPSocket,
    job_queue: *JobQueue,
    id: ID,
    frame: @Frame(accept_loop) = undefined,
    routing: *index.routing.RoutingTable,

    broadcast_hooks: std.ArrayList(HookType),
    direct_message_hooks: std.ArrayList(HookType),

    pub fn init(address: net.Address) !*UDPServer {
        var server = try default.allocator.create(UDPServer);
        server.* = .{
            .records = std.ArrayList(*Record).init(default.allocator),
            .ip_index = std.StringHashMap(*Record).init(default.allocator),
            .id_index = std.AutoHashMap(ID, *Record).init(default.allocator),
            .address = address,
            .socket = try UDPSocket.init(address),
            .job_queue = try JobQueue.init(server),
            .id = id_.rand_id(),
            .routing = try index.routing.RoutingTable.init(server.id, default.n_fingers),
            .broadcast_hooks = std.ArrayList(HookType).init(default.allocator),
            .direct_message_hooks = std.ArrayList(HookType).init(default.allocator),
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
        server.address = server.socket.getAddress();
        server.job_queue.start_job_loop();
        server.frame = async server.accept_loop();
    }

    pub fn wait(server: *UDPServer) !void {
        try await server.frame;
    }

    fn accept_loop(server: *UDPServer) !void {
        while (true) {
            std.log.info("Getting", .{});
            const msg = try server.socket.recvFrom();
            std.log.info("got msg:{s}", .{utils.hex(msg.buf)});

            try server.routing.add_address_seen(msg.from);

            // Update / Add record
            if (!try server.verify_address(msg.from)) {
                continue;
            }

            try server.job_queue.enqueue(.{ .inbound_message = msg });
        }
    }

    pub fn send(server: *UDPServer, id: ID, buf: []const u8) !void {
        if (server.id_index.get(id)) |record| {
            server.socket.sendTo(record.address, buf);
        } else {
            return error.IDNotInRecords;
        }
    }

    fn verify_address(server: *UDPServer, address: net.Address) !bool {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{address});
        if (server.ip_index.get(ip_string)) |record| {
            //known
            record.last_connect = time.milliTimestamp();
            if (record.red_flags > 1) //drop message
            {
                std.log.info("Dropping red-flag message, flags: {}", .{record.red_flags});
                return false;
            }
        } else {
            var record = try default.allocator.create(Record);
            record.* = .{
                .address = address,
                .last_connect = time.milliTimestamp(),
            };

            try server.records.append(record);
            try server.ip_index.put(ip_string, record);
        }
        return true;
    }

    pub fn get_closest_record(server: *UDPServer, id: ID) ?Record {
        var best_record: ?Record = null;
        var lowest_dist = std.mem.zeroes(ID);

        for (server.records.items) |record| {
            if (id_.is_zero(record.id))
                continue;

            const dist = id_.xor(id, record.id);
            if (id_.is_zero(lowest_dist) or id_.less(dist, lowest_dist)) {
                lowest_dist = dist;
                best_record = record.*;
            }
        }
        return best_record;
    }

    pub fn get_record_by_ip(server: *UDPServer, address: std.net.Address) ?Record {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{address});
        return server.ip_index.get(ip_string);
    }

    pub fn get_record_by_id(server: *UDPServer, id: ID) ?Record {
        return server.id_index.get(id);
    }

    pub fn update_ip_id_pair(server: *UDPServer, addr: std.net.Address, id: ID) !void {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});

        if (server.ip_index.get(ip_string)) |record| {
            record.id = id;

            try server.id_index.put(id, record);
            try server.ip_index.put(ip_string, record);
        } else {
            // create new record
            var record = try default.allocator.create(Record);
            record.* = .{
                .id = id,
                .address = addr,
                .last_connect = time.milliTimestamp(),
            };
            try server.records.append(record);

            try server.id_index.put(id, record);
            try server.ip_index.put(ip_string, record);
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
