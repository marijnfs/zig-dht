// unique id for message work

const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const ID = index.ID;
const Hash = index.Hash;

pub fn unicodeToInt32(unicode: u21) !u32 {
    var code: u32 = 0;
    _ = try std.unicode.utf8Encode(unicode, std.mem.bytesAsSlice(u8, std.mem.asBytes(&code)));
    return code;
}

pub fn calculate_hash(data: []const u8) ID {
    var result: ID = undefined;
    std.crypto.hash.Blake3.hash(data, result[0..], .{});
    return result;
}

pub fn calculate_hash_multiple(data_list: [][]const u8) Hash {
    var hasher = std.crypto.hash.Blake3.init(.{});
    for (data_list) |data| {
        hasher.update(data);
    }
    var result: Hash = undefined;
    hasher.final(result[0..]);
    return result;
}

pub fn random_selection(K: usize, N: usize) ![]usize {
    std.log.debug("random selection:{} {}", .{ K, N });
    var ks = try default.allocator.alloc(usize, if (K < N) K else N);
    var ns = try default.allocator.alloc(usize, N);
    defer default.allocator.free(ns);
    var i: usize = 0;
    while (i < ns.len) : (i += 1) {
        ns[i] = i;
    }

    index.rng.random().shuffle(usize, ns);
    var k: usize = 0;
    while (k < ks.len) : (k += 1) {
        ks[k] = ns[k];
        std.log.debug("random k: {}, {}", .{ k, ns[k] });
    }
    return ks;
}
