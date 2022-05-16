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

const UDPSocket = index.UDPSocket;
const Hash = index.Hash;
const id_ = index.id;
const ID = index.ID;

const JobQueue = index.JobQueue(ServerJob, *UDPServer);

const UDPServer = struct {
    const Record = struct {
        address: net.Address = undefined,
        id: ID = std.mem.zeroes(ID),
        red_flags: usize = 0,
        last_connect: i64 = 0,
    };

    records: std.ArrayList(*Record),
    ip_index: std.StringHashMap(*Record),
    id_index: std.AutoHashMap(ID, *Record),
    address: net.Address,
    socket: *UDPSocket,
    job_queue: *JobQueue,
    id: ID,
    frame: @Frame(accept_loop) = undefined,

    fn init(address: net.Address) !*UDPServer {
        var server = try default.allocator.create(UDPServer);
        server.records = std.ArrayList(*Record).init(default.allocator);
        server.ip_index = std.StringHashMap(*Record).init(default.allocator);
        server.id_index = std.AutoHashMap(ID, *Record).init(default.allocator);
        server.address = address;
        server.socket = try UDPSocket.init(address);
        server.job_queue = try JobQueue.init(server);
        server.id = id_.rand_id();
        return server;
    }

    fn deinit(server: *UDPServer) void {
        server.socket.deinit();
        default.allocator.destroy(server);
    }

    fn start(server: *UDPServer) void {
        std.log.info("Starting UDP Server", .{});

        server.job_queue.start_job_loop();

        server.frame = async server.accept_loop();
    }

    fn accept_loop(server: *UDPServer) !void {
        while (true) {
            const msg = try server.socket.recvFrom();

            // Update / Add record
            const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{msg.from});
            if (server.ip_index.get(ip_string)) |record| {
                //known
                record.last_connect = time.milliTimestamp();
                if (record.red_flags > 1) //drop message
                {
                    std.log.info("Dropping red-flag message", .{});
                    continue;
                }
            } else {
                var record = try default.allocator.create(Record);
                record.address = msg.from;
                record.last_connect = time.milliTimestamp();

                try server.records.append(record);
                try server.ip_index.put(ip_string, record);
            }

            try server.job_queue.enqueue(.{ .inbound_message = msg });
        }
    }

    fn send(server: *UDPServer, id: ID, buf: []const u8) !void {
        if (server.id_index.get(id)) |record| {
            server.socket.sendTo(record.address, buf);
        } else {
            return error.IDNotInRecords;
        }
    }

    fn get_closest_record(server: *UDPServer, id: ID) ?Record {
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
};

// Jobs
// Main application logic
pub const ServerJob = union(enum) {
    connect: std.net.Address,
    send_message: communication.OutboundMessage,
    inbound_message: index.socket.UDPIncoming,
    process_message: communication.Envelope,
    broadcast: communication.Envelope,
    callback: fn () anyerror!void,

    pub fn work(self: *ServerJob, queue: *JobQueue, server: *UDPServer) !void {
        switch (self.*) {
            .connect => |address| {
                if (default.server.apparent_address) |apparent_address| {
                    if (std.net.Address.eql(address, apparent_address)) {
                        std.log.info("Asked to connect to our own apparent ip, ignoring", .{});
                        return;
                    }
                }

                const content = communication.Content{ .ping = .{ .source_id = server.id, .source_port = server.address.getPort() } };
                const envelope = communication.Envelope{ .source_id = server.id, .nonce = id_.get_guid(), .content = content };
                try queue.enqueue(.{ .send_message = .{ .target = .{ .address = address }, .payload = .{ .envelope = envelope } } });
            },
            .process_message => |envelope| {
                const guid = 0;
                try communication.process_message(envelope, guid);
            },
            // Multi function send message,
            // both for incoming and outgoing messages
            .send_message => |outbound_message| {
                const payload = outbound_message.payload;

                const data = switch (payload) {
                    .raw => |raw_data| raw_data,
                    .envelope => |envelope| b: {
                        const serial_message = try serial.serialise(envelope);
                        defer default.allocator.free(serial_message);
                        const hash_message = try hash.append_hash(serial_message);
                        std.log.info("send message with hash of: {}", .{utils.hex(&hash_message.hash)});
                        try model.add_hash(hash_message.hash);
                        break :b hash_message.slice;
                    },
                };
                switch (outbound_message.target) {
                    .address => |address| {
                        try server.socket.sendTo(address, data);
                    },
                    .id => |id| {
                        if (server.id_index.get(id)) |record| { //direct match
                            try server.socket.sendTo(record.address, data);
                            return;
                        }

                        if (server.get_closest_record(id)) |record| {
                            try server.socket.sendTo(record.address, data);
                        } else {
                            //failed to find any valid record
                            std.log.info("Failed to find any record for id {}", .{utils.hex(&id)});
                        }
                    },
                    else => {
                        unreachable;
                    },
                }
            },
            .inbound_message => |inbound_message| {
                var data_slice = inbound_message.buf;

                var hash_slice = try hash.calculate_and_check_hash(data_slice);

                if (try model.check_and_add_hash(hash_slice.hash)) {
                    std.log.info("message dropped, already seen", .{});
                    return;
                }

                var envelope = try serial.deserialise(communication.Envelope, &hash_slice.slice);

                if (id_.is_zero(envelope.target_id) or id_.is_equal(envelope.target_id, default.server.id)) {
                    std.log.info("message is for me", .{});
                    try queue.enqueue(.{ .process_message = envelope });
                } else {
                    try queue.enqueue(.{ .send_message = .{ .target = .{ .id = envelope.target_id }, .payload = .{ .raw = data_slice } } });
                }

                std.log.info("process forward message: {any}", .{envelope});
            },
            .broadcast => |broadcast_envelope| {
                std.log.info("broadcasting: {s}", .{broadcast_envelope});
                for (server.records.items) |record| {
                    try queue.enqueue(.{ .send_message = .{ .target = .{ .address = record.address }, .payload = .{ .envelope = broadcast_envelope } } });
                }
            },
            .callback => |callback| {
                try callback();
            },
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
