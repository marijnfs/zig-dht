const dht = @import("dht");
const clap = @import("zig-clap");
const std = @import("std");

const ID = dht.ID;
const hex = dht.hex;

const debug = std.info;
const io = std.io;

const allocator = std.heap.page_allocator;
var username: []const u8 = undefined;

pub fn main() !void {

    // Setup server
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                    Display this help and exit.
        \\-i, --ip <str>                  
        \\-p, --port <u16>                
        \\--remote_ip <str>            
        \\--remote_port <u16>          Remote port
        \\-u, --username  <str>        UserName
        \\--public                 This is a public node
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();
    const args = res.args;

    if (args.help)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    username = args.username orelse return error.MissingUsername;

    try dht.init();
    const address = try std.net.Address.parseIp(args.ip.?, args.port.?);
    var id = dht.id.rand_id();

    var server = try dht.server.Server.init(address, id, .{ .public = args.public });
    defer server.deinit();

    if (args.remote_ip != null and args.remote_port != null) {
        const address_remote = try std.net.Address.parseIp(args.remote_ip.?, args.remote_port.?);
        try server.routing.add_address_seen(address_remote);
        try server.job_queue.enqueue(.{ .connect = .{ .address = address_remote, .public = true } });
    }

    // try server.add_direct_message_hook(direct_message_hook);
    try server.add_broadcast_hook(broadcast_hook);

    _ = try std.Thread.spawn(.{}, read_and_send, .{server});

    try server.start();
    try server.wait();
}

const Api = union(enum) {
    msg: struct {
        username: []const u8,
        message: []const u8,
    },
};

fn broadcast_hook(buf: []const u8, src_id: ID, src_address: std.net.Address, server: *dht.Server) !bool {
    std.log.info("broadcast hook", .{});
    _ = src_address;
    const message = try dht.serial.deserialise_slice(Api, buf, allocator);
    std.log.info("id:{} broadcast from:{}", .{ hex(server.id[0..8]), hex(src_id[0..8]) });

    // Verify the block
    switch (message) {
        .msg => |msg| {
            try std.io.getStdOut().writer().print("{s}: {s}", .{ msg.username, msg.message });
        },
    }

    return true;
}

pub fn read_and_send(server: *dht.Server) !void {
    nosuspend {
        var stdin = std.io.getStdIn();
        stdin.intended_io_mode = .blocking;
        var stdout = std.io.getStdOut();
        stdout.intended_io_mode = .blocking;

        var buf: [100]u8 = undefined;
        while (true) {
            const slice_opt = try stdin.reader().readUntilDelimiterOrEof(buf[0..], '\n');
            const slice = slice_opt orelse {
                std.log.debug("Std in ended", .{});
                break;
            };
            std.log.debug("read line", .{});

            // send req broadcast
            const msg = Api{ .msg = .{
                .username = username,
                .message = try allocator.dupe(u8, slice),
            } };
            const send_buf = try dht.serial.serialise_alloc(msg, allocator);
            try server.queue_broadcast(send_buf);

            if (std.mem.eql(u8, slice, "finger")) {
                try stdout.writeAll("fingers:\n");
                try server.finger_table.summarize(stdout.writer());
                try stdout.writeAll("public fingers:\n");
                try server.public_finger_table.summarize(stdout.writer());
                try server.routing.summarize(stdout.writer());
            }
        }
    }
}
