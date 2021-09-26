// unique id for message work

const std = @import("std");
const index = @import("index.zig");
const default = index.default;

const ID = index.ID;

var rng = std.rand.DefaultPrng.init(0);
var root_guid: u64 = undefined;

// Call this ones to initialize the Guid
pub const hex = std.fmt.fmtSliceHexLower;

pub fn init() void {
    std.log.info("utils.init", .{});
const seed = 42; //std.crypto.random.int(u64);
    rng = std.rand.DefaultPrng.init(seed);

    root_guid = rng.random.int(u64);
}

pub fn get_guid() u64 {
    const order = std.builtin.AtomicOrder.Monotonic;
    var val = @atomicRmw(u64, &root_guid, .Add, 1, order);
    return val;
}

pub fn get_finger_id(id: ID, bit: usize) ID {
    // 256 bits = 64 bytes
    // We find the index in the byte (bit_id)
    // We find the byte (byte_id)
    const byte_id: usize = bit / 8;
    const bit_position: u3 = @intCast(u3, bit % 8);

    // convert to bit index
    const bit_id: u3 = @intCast(u3, 7 - bit_position);

    var new_id = id;
    new_id[byte_id] = id[byte_id] ^ (@as(u8, 1) << bit_id); //xor byte with bit in correct place
    return new_id;
}

pub fn xor(id1: ID, id2: ID) ID {
    var result: ID = id1;
    for (result) |r, i| {
        result[i] = r ^ id2[i];
    }
    return result;
}

pub fn less(id1: ID, id2: ID) bool {
    return std.mem.order(u8, id1[0..], id2[0..]) == .lt;
}

pub fn rand_id() ID {
    var id: ID = undefined;
    rng.random.bytes(&id);
    std.log.info("randid: {any}", .{id});
    return id;
}

pub fn calculate_hash(data: []const u8) ID {
    var result: ID = undefined;
    std.crypto.hash.Blake3.hash(data, result[0..], .{});
    return result;
}

pub fn id_is_zero(id: ID) bool {
    return std.mem.eql(u8, &id, &std.mem.zeroes(ID));
}

pub fn id_is_equal(id: ID, id2: ID) bool {
    return std.mem.eql(u8, &id, &id2);
}

pub fn random_selection(K: usize, N: usize) ![]usize {
    std.log.info("random selection:{} {}", .{ K, N });
    var ks = try default.allocator.alloc(usize, if (K < N) K else N);
    var ns = try default.allocator.alloc(usize, N);
    defer default.allocator.free(ns);
    var i: usize = 0;
    while (i < ns.len) : (i += 1) {
        ns[i] = i;
    }

    rng.random.shuffle(usize, ns);
    var k: usize = 0;
    while (k < ks.len) : (k += 1) {
        ks[k] = ns[k];
        std.log.info("random k: {}, {}", .{ k, ns[k] });
    }
    return ks;
}
