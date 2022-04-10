const std = @import("std");

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const id_ = index.id;

const Hash = index.Hash;

const RetType = struct { hash: Hash, slice: []u8 };

pub fn calculate_and_check_hash(data_slice: []u8) !RetType {
    if (data_slice.len < @sizeOf(Hash)) {
        std.log.info("message dropped", .{});
        return error.TooShort;
    }

    const reported_hash: Hash = data_slice[0..@sizeOf(Hash)].*;
    const body_slice = data_slice[@sizeOf(Hash)..];
    const calculated_hash = utils.calculate_hash(body_slice);
    if (!id_.is_equal(reported_hash, calculated_hash)) {
        std.log.info("message dropped, hash doesn't match", .{});
        return error.FalseHash;
    }
    return RetType{ .hash = calculated_hash, .slice = body_slice };
}

pub fn append_hash(data_slice: []u8) !RetType {
    const hash = utils.calculate_hash(data_slice);

    const hash_message = try default.allocator.alloc(u8, hash.len + data_slice.len);
    std.mem.copy(u8, hash_message[0..hash.len], &hash);
    std.mem.copy(u8, hash_message[hash.len..], data_slice);
    return RetType{ .hash = hash, .slice = hash_message };
}
