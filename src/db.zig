const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const ID = index.ID;
const Hash = index.Hash;

const Blob = []u8;
const MaxBlobSize = 64 << 10;

pub var database: Database = undefined;

pub fn init() !void {
    try database.init();
}

const Database = struct {
    store: std.AutoHashMap(ID, Blob),

    pub fn init(db: *Database) !void {
        db.store = std.AutoHashMap(ID, Blob).init(default.allocator);
    }

    pub fn put(db: *Database, data: Blob) !ID {
        if (data.len > MaxBlobSize)
            return error.BlobTooLarge;
        const id = utils.calculate_hash(data);
        try db.store.put(id, std.mem.sliceAsBytes(data));
        return id;
    }

    pub fn get(db: *Database, id: ID) ?[]u8 {
        return db.store.get(id);
    }

    pub fn contains(db: *Database, id: ID) bool {
        return db.store.contains(id);
    }
};
