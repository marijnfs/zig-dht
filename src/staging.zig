// Staging area; where new functions that don't have a place yet can be put

const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;

pub fn expand_connections() void {
    const n_connections = count_connections();
    std.log.info("n connection: {}", .{n_connections});
}

pub fn sync_finger_table() void {}

pub fn refresh_finger_table() void {}

pub fn count_connections() usize {
    var n_connections = default.server.incoming_connections.count();
    for (jobs.job_queue.slice()) |job| {
        if (job == .connect) {
            n_connections += 1;
        }
    }
    return n_connections;
}

// pub fn clear_closed_connections(server: *Server) void {
// Todo, don't use remove inside loop; invadlidates the iterator

// var it_in = server.incoming_connections.keyIterator();
// while (it_in.next()) |conn| {
//     if (conn.*.state == .Disconnected)
//         server.out_going_connections.remove(conn.*);
// }

// var it_out = server.outgoing_connections.keyIterator();
// while (it_out.next()) |conn| {
//     if (conn.*.state == .Disconnected)
//         server.out_going_connections.remove(conn.*);
// }
// }
