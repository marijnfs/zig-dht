const std = @import("std");
const index = @import("index.zig");
const utils = index.utils;

// Common types
const ID_SIZE = 32;
pub const ID = [ID_SIZE]u8;
pub const Hash = [ID_SIZE]u8;

var root_guid: u64 = undefined;

pub fn init() void {
    root_guid = index.rng.random().int(u64);
}

pub fn get_guid() u64 {
    const order = std.builtin.AtomicOrder.Monotonic;
    var val = @atomicRmw(u64, &root_guid, .Add, 1, order);
    return val;
}

pub fn xor_bitpos(id: ID, bit: usize) ID {
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
    index.rng.random().bytes(&id);
    std.log.info("randid: {any}", .{id});
    return id;
}

pub fn is_zero(id: ID) bool {
    return std.mem.eql(u8, &id, &std.mem.zeroes(ID));
}

pub fn is_equal(id: ID, id2: ID) bool {
    return std.mem.eql(u8, &id, &id2);
}
