pub const io_mode = .evented; // use event loop

const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const timer = index.timer;
const jobs = index.jobs;
const routing = index.routing;
const staging = index.staging;

const c = index.c;
const Server = index.Server;
const ID = index.ID;

pub const log_level: std.log.Level = .warn;

pub fn time_test() void {
    std.log.info("timer", .{});
}

// pub fn handle_key(key: i32) !void {}

// pub fn handle_special_key(key: i32) !void {}

// pub fn handle_broadcast(msg: []u8, src: ID) !void {}

// pub fn handle_render() !void {}

fn filetest() !void {
    // var file = try std.fs.cwd().openFile("foo.txt", .{});
    // defer file.close();

    // while (true) {
    //     var buf: [64 << 10]u8 = undefined;
    //     const read = try file.read(&buf);
    //     if (read == 0)
    //         break;

    //     const blob = try std.mem.dupe(default.allocator, u8, buf[0..read]);
    //     _ = try index.db.database.put(blob);
    // }

    // const tmp: []u8 = try default.allocator.alloc(u8, 10);
    // tmp[0] = 42;
    // const id = try index.db.database.put(tmp);
    // const blob = index.db.database.get(id);
    // std.log.info("id: {any}", .{id});
    // std.log.info("blob: {any}", .{blob});
    // std.log.info("read: {any}", .{index.db.database.store.count()});

    var cwd = std.fs.cwd();
    var dir = try cwd.openDir("test", .{ .iterate = true });
    // var dir = try std.fs.openDirAbsolute("test", .{ .iterate = true });

    var walker = try dir.walk(default.allocator);
    while (try walker.next()) |entry| {
        std.log.err("entry {}", .{entry});
    }
    unreachable;
}

pub fn main() !void {
    var args = try std.process.argsAlloc(default.allocator);
    defer std.process.argsFree(default.allocator, args);
    std.log.info("arg0 {s}", .{args[0]});

    if (args.len < 4) {
        std.log.err("Usage: {s} [username] [localip] [localport] ([remote ip] [remote port])*", .{args[0]});
        return error.MissingUsername;
    }

    try index.init();
    defer index.deinit();

    try timer.add_timer(10000, staging.expand_connections, true);
    try timer.add_timer(20000, staging.refresh_finger_table, true);
    try timer.add_timer(30000, staging.sync_finger_table, true);
    try timer.add_timer(30000, staging.clear_closed_connections, true);
    try timer.add_timer(60000, staging.detect_self_connection, true);

    {
        const servername = try default.allocator.dupe(u8, args[2]);
        const username = try default.allocator.dupe(u8, args[1]);
        const port = try std.fmt.parseInt(u16, args[3], 0);

        default.server = try Server.create(.{ .name = servername, .username = username, .port = port });

        try default.server.initialize();
    }

    if (args.len >= 5) {
        const port = try std.fmt.parseInt(u16, args[5], 0);
        const addr = try std.net.Address.parseIp(args[4], port);
        try routing.add_address_seen(addr);
        try jobs.enqueue(.{ .connect = addr });
    }

    std.log.info("Spawning Server Thread..", .{});
    var server_frame = async default.server.start();
    try routing.init_finger_table();

    std.log.info("Server ID: {Server ID}", .{utils.hex(&default.server.id)});

    // start timers
    try timer.start_timer_thread();

    std.log.info("Starting Job loop", .{});

    try jobs.job_loop();
    _ = server_frame;
    unreachable;
    // try await server_frame;
}
