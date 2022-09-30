const dht = @import("dht");
const clap = @import("clap");
const std = @import("std");

const ID = dht.ID;

const debug = std.debug;
const io = std.io;

pub fn main() !void {
    // const allocator = std.heap.page_allocator;

    // Setup server
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                    Display this help and exit.
        \\--ip <str>                   Display this help and exit.
        \\--port <u16>                   Display this help and exit.
        \\--remote_ip <str>                   Display this help and exit.
        \\--remote_port <u16>                   Display this help and exit.
        \\-n, --name                   UserName
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

    try dht.init();
    const address = try std.net.Address.parseIp(args.ip.?, args.port.?);
    var id = dht.id.rand_id();
    if (args.zero_id) {
        id = dht.id.zeroes();
        id[0] = 1;
    }

    var server = try dht.server.Server.init(address, id, .{ .public = args.public });
    defer server.deinit();

    if (args.remote_ip != null and args.remote_port != null) {
        const address_remote = try std.net.Address.parseIp(args.remote_ip.?, args.remote_port.?);
        try server.routing.add_address_seen(address_remote);
        try server.job_queue.enqueue(.{ .connect = .{ .address = address_remote, .public = true } });
    }

    // try server.add_direct_message_hook(direct_message_hook);
    try server.add_broadcast_hook(broadcast_hook);

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
    _ = src_address;
    const message = try dht.serial.deserialise_slice(Api, buf, allocator);
    std.log.info("id:{} broadcast from:{}", .{ hex(server.id[0..8]), hex(src_id[0..8]) });

    // Verify the block
    switch (message) {
        .block => |block| {
            const t = time.milliTimestamp();
            if (t - farmer_settings.accept_delay > block.total_embargo and block.total_difficulty > chain_head.total_difficulty) {
                try debug_msg(
                    try std.fmt.allocPrint(allocator, "t{} id:{} hash:{} other:{}\n", .{
                        std.time.milliTimestamp(),
                        hex(server.id[0..8]),
                        hex(block.hash[0..8]),
                        hex(src_id[0..8]),
                    }),
                    server,
                );
                std.log.debug("block total difficulty: {}, chain head: {}", .{ block.total_difficulty, chain_head.total_difficulty });

                if (block_db.get(block.prev)) |head| {
                    var block_copy = block;
                    try block_copy.rebuild(head);
                    if (!std.mem.eql(u8, std.mem.asBytes(&block), std.mem.asBytes(&block_copy))) {
                        std.log.warn("Block rebuild failed, rejecting \n{} \n{}", .{ block, block_copy });
                        return error.FalseRebuild;
                    }
                } else {
                    std.log.debug("Don't have head, accepting blindly", .{}); //TODO: replace with proper syncing method
                }

                {
                    std.log.info("Accepting received block", .{});
                    best_block_mutex.lock();
                    defer best_block_mutex.unlock();

                    try accept_block(block, server);
                }
            } else {
                try debug_msg(
                    try std.fmt.allocPrint(allocator, "not accepting t{} id:{} hash:{} other:{}\n", .{
                        std.time.milliTimestamp(),
                        hex(server.id[0..8]),
                        hex(block.hash[0..8]),
                        hex(src_id[0..8]),
                    }),
                    server,
                );
                std.log.debug("not accepting block {}: from {}, other diff:{} mine diff:{}", .{ hex(block.hash[0..8]), hex(src_id[0..8]), block.total_difficulty, chain_head.total_difficulty });
            }
        },
        .req => {
            const msg = Api{ .rep = try std.fmt.allocPrint(allocator, "my head {} diff: {}", .{ hex(chain_head.hash[0..8]), chain_head.total_difficulty }) };
            const send_buf = try dht.serial.serialise_alloc(msg, allocator);

            try server.queue_direct_message(src_id, send_buf);
            std.log.debug("I {} got req, direct reply", .{hex(server.id[0..8])});
        },
        .rep => |rep| {
            std.log.debug("Got Rep from: {} {s}", .{ hex(src_id[0..8]), rep });
        },
        else => {},
    }

    return true;
}
