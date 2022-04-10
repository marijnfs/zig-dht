// File containing main operations, or 'Jobs'
// They can be scheduled from various places and run in sequence in the main event loop
// These Jobs form the main synchronising organising principle. Jobs can do complex tasks as they are guaranteed to operate alone.

const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const communication = index.communication;
const serial = index.serial;
const utils = index.utils;
const connections = index.connections;
const model = index.model;
const jobs = index.jobs;
const c = index.c;
const hash = index.hash;
const id_ = index.id;

const AtomicQueue = index.AtomicQueue;
const ID = index.ID;
const Hash = index.Hash;

pub var job_queue: AtomicQueue(*Job) = undefined;

pub fn init() void {
    job_queue = AtomicQueue(*Job).init(default.allocator);
}

pub fn enqueue(job: Job) !void {
    const job_ptr = try default.allocator.create(Job);
    job_ptr.* = job;
    std.log.info("queuing job: {}\n", .{job});
    try job_queue.push(job_ptr);
}

pub fn job_loop() !void {
    while (true) {
        if (job_queue.pop()) |job| {
            // const stdout = std.io.getStdOut().writer();
            // nosuspend stdout.print("job: {any}\n", .{job}) catch unreachable;
            // const data = try std.fmt.allocPrint(default.allocator, "job: {any}\n", .{job});
            // c.print(data);
            std.log.info("Work: {}", .{job});
            job.work() catch |e| {
                std.log.info("Work Error: {}", .{e});
            };
            default.allocator.destroy(job);
        } else {
            //sleep
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }
}

// Jobs
// Main application logic
pub const Job = union(enum) {
    render: bool,
    broadcast: communication.Message,
    connect: std.net.Address,
    send_message: communication.Envelope,
    inbound_forward_message: communication.InboundMessage,
    inbound_backward_message: communication.InboundMessage,
    print: []u8,
    print32: []u32,
    print_msg: struct { user: []u8, msg: []u32 },
    process_forward: struct {
        guid: u64,
        message: communication.Message,
    },
    process_backward: struct {
        guid: u64,
        message: communication.Message,
    },
    callback: fn () anyerror!void,
    fn work(self: *Job) !void {
        switch (self.*) {
            .process_forward => |guid_message| {
                const message = guid_message.message;
                const guid = guid_message.guid;
                try communication.process_forward(message, guid);
            },
            .process_backward => |guid_message| {
                const message = guid_message.message;
                const guid = guid_message.guid;
                try communication.process_backward(message, guid);
            },
            // Multi function send message,
            // both for incoming and outgoing messages
            .send_message => |envelope| {
                const payload = envelope.payload;

                const data = switch (payload) {
                    .raw => |raw_data| raw_data,
                    .message => |message| blk: {
                        const serial_message = try serial.serialise(message);
                        defer default.allocator.free(serial_message);
                        const hash_message = try hash.append_hash(serial_message);
                        std.log.info("send message with hash of: {}", .{utils.hex(&hash_message.hash)});
                        try model.add_hash(hash_message.hash);
                        break :blk hash_message.slice;
                    },
                };
                switch (envelope.target) {
                    .guid => |guid| {
                        // first find the ingoing or outgoing connection
                        var in_it = default.server.incoming_connections.keyIterator();
                        while (in_it.next()) |connection| {
                            if (connection.*.guid == guid) {
                                try connection.*.write(data);
                                break;
                            }
                        }

                        var out_it = default.server.outgoing_connections.keyIterator();
                        while (out_it.next()) |connection| {
                            if (connection.*.guid == guid) {
                                try connection.*.write(data);
                                break;
                            }
                        }
                    },
                    .id => |id| {
                        var best_connection = default.server.get_closest_outgoing_connection(id);

                        if (best_connection) |connection| {
                            try connection.*.write(data);
                        } else {
                            std.log.info("Couldn't route {}", .{utils.hex(&id)});
                        }
                    },
                }
            },
            .inbound_forward_message => |inbound_message| {
                var data_slice = inbound_message.content;

                var hash_slice = try hash.calculate_and_check_hash(data_slice);

                if (try model.check_and_add_hash(hash_slice.hash)) {
                    std.log.info("message dropped, already seen", .{});
                    return;
                }

                var message = try serial.deserialise(communication.Message, &hash_slice.slice);

                if (id_.is_zero(message.target_id) or id_.is_equal(message.target_id, default.server.id)) {
                    std.log.info("message is for me", .{});
                    try jobs.enqueue(.{ .process_forward = .{ .guid = inbound_message.guid, .message = message } });
                } else {
                    try jobs.enqueue(.{ .send_message = .{ .target = .{ .id = message.target_id }, .payload = .{ .raw = data_slice } } });
                }

                std.log.info("process forward message: {any}", .{message});
            },
            .inbound_backward_message => |inbound_message| {
                var data_slice = inbound_message.content;
                // const hash = message.hash;

                var hash_slice = try hash.calculate_and_check_hash(data_slice);
                if (try model.check_and_add_hash(hash_slice.hash)) {
                    std.log.info("message dropped, already seen", .{});
                    return;
                }

                data_slice = hash_slice.slice;
                const message = try serial.deserialise(communication.Message, &data_slice);

                std.log.info("process backward message: {any}", .{message});

                if (id_.is_equal(message.target_id, default.server.id)) {
                    std.log.info("for me, target_id: {}", .{utils.hex(&message.target_id)});

                    try jobs.enqueue(.{ .process_backward = .{ .guid = inbound_message.guid, .message = message } });
                } else {
                    std.log.info("pass on, target_id: {}", .{utils.hex(&message.target_id)});
                    try jobs.enqueue(.{ .send_message = .{ .target = .{ .id = message.target_id }, .payload = .{ .raw = data_slice } } });
                }
            },

            .broadcast => |broadcast_message| {
                std.log.info("broadcasting: {s}", .{broadcast_message});
                var it = default.server.outgoing_connections.keyIterator();
                while (it.next()) |conn| {
                    try jobs.enqueue(.{ .send_message = .{ .target = .{ .guid = conn.*.guid }, .payload = .{ .message = broadcast_message } } });
                }

                // Backward routing (might not be a good idea)
                var it_back = default.server.incoming_connections.keyIterator();
                while (it_back.next()) |conn| {
                    try jobs.enqueue(.{ .send_message = .{ .target = .{ .guid = conn.*.guid }, .payload = .{ .message = broadcast_message } } });
                }
            },

            .connect => |address| {
                if (default.server.apparent_address) |apparent_address| {
                    if (std.net.Address.eql(address, apparent_address)) {
                        std.log.info("Asked to connect to our own apparent ip, ignoring", .{});
                        return;
                    }
                }

                std.log.info("Connect {s}, sending ping: {}", .{ address, utils.hex(&default.server.id) });
                const out_connection = try default.server.connect_and_add(address);
                std.log.info("Connected {s}", .{address});
                const content = communication.Content{ .ping = .{ .source_id = default.server.id, .source_port = default.server.config.port } };
                const message = communication.Message{ .source_id = default.server.id, .nonce = id_.get_guid(), .content = content };
                try enqueue(.{ .send_message = .{ .target = .{ .guid = out_connection.guid }, .payload = .{ .message = message } } });
            },
            .callback => |callback| {
                try callback();
            },
            .print => |buf| {
                c.print32(std.mem.bytesAsSlice(u32, @alignCast(4, buf)));
                // c.print(buf);
                // const stdout = std.io.getStdOut().writer();
                // nosuspend _ = try stdout.print("print: {s}\n", .{print});
            },
            .print32 => |print| {
                c.print32(print);
                // const stdout = std.io.getStdOut().writer();
                // nosuspend _ = try stdout.print("print: {s}\n", .{print});
            },
            .print_msg => |print_msg| {
                c.print_msg(print_msg.user, print_msg.msg);
            },
            .render => {
                c.render();
            },
        }
    }
};
