const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const ID = index.ID;
const Hash = index.Hash;

const Blob = []const u8;
const MaxBlobSize = 64 << 10; //64KB

// Simple Persistent Blob Database
// Blobs are stored under their Hash value
// The hash is returned in the put(Blob) function, and can be used to get() the value back

pub const Database = struct {
    store: std.AutoHashMap(ID, Blob),
    store_dir: std.fs.Dir,

    pub fn init(path: []const u8) !*Database {
        var db = try default.allocator.create(Database);
        db.* = .{
            .store = std.AutoHashMap(ID, Blob).init(default.allocator),
        };
        try db.open_directory(path);

        return db;
    }

    pub fn deinit(db: *Database) void {
        db.store.deinit();
        db.store_dir.close();
    }

    pub fn put(db: *Database, data: Blob) !ID {
        if (data.len > MaxBlobSize)
            return error.BlobTooLarge;
        const id = utils.calculate_hash(data);

        try db.store.put(id, data);
        try db.put_persistent(id, data);

        return id;
    }

    pub fn get(db: *Database, id: ID) !Blob {
        if (db.store.get(id)) |value| {
            return value;
        }

        const data = try db.get_persistent(id);

        //store back in fast storage
        try db.store.put(id, data);

        return data;
    }

    // explicitly allows to store non-matching id/data if you want
    // this can be used to store root files, will however show up as errors in a raw consistency check
    // but that is expected behaviour (consistency check should not remove the file / maybe adds its under it's direct hash as well)
    pub fn put_persistent(db: *Database, id: ID, data: Blob) !void {
        var path = try idToFilepath(id);
        std.log.info("put_persistent, {s}", .{path});

        // Make dir to be sure
        var dir_path = try idToDirpath(id);
        std.log.info("dir path, {s}", .{dir_path});

        db.store_dir.makeDir(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {
                std.log.info("exists", .{});
            },
            else => return err,
        };

        // Create file
        var file = try db.store_dir.createFile(path, .{});
        //db.store_dir.createFile(path, .{.truncate = false, .read = true}); //possibility, leave if already read

        //Write data to file
        try file.writer().writeAll(data);
    }

    pub fn get_persistent(db: *Database, id: ID) !Blob {
        var path = try idToFilepath(id);

        var file = db.store_dir.openFile(path, .{}) catch {
            return error.NotFound;
        };

        var buf = try default.allocator.alloc(u8, MaxBlobSize);
        defer default.allocator.free(buf);

        const len = try file.reader().readAll(buf);
        return try default.allocator.dupe(u8, buf[0..len]);
    }

    pub fn contains(db: *Database, id: ID) bool {
        return db.store.contains(id);
    }

    pub fn open_directory(db: *Database, path: []const u8) !void {
        std.fs.cwd().makeDir(path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        db.store_dir = try std.fs.cwd().openDir(path, .{ .iterate = true, .no_follow = true });
    }

    fn idToFilepath(id: ID) ![]const u8 {
        var path = try std.fmt.allocPrint(default.allocator, "{s}/{s}", .{ utils.hex(id[0..1]), utils.hex(id[1..id.len]) });
        return path;
    }

    // only returns dir that would contain the file
    fn idToDirpath(id: ID) ![]const u8 {
        var path = try std.fmt.allocPrint(default.allocator, "{s}", .{utils.hex(id[0..1])});
        return path;
    }
};

test "test basics" {
    var database = try Database.init("test");
    defer database.deinit();

    const data = "sdf";
    const data_id = try database.put(data);

    try std.testing.expectEqualSlices(u8, &data_id, &utils.calculate_hash(data));

    std.log.info("store id {s}", .{utils.hex(&data_id)});

    var loaded = try database.get(data_id);

    std.log.info("loaded: {s}", .{loaded});
    _ = database.store.remove(data_id);
    std.log.info("removing from memory: {s}", .{utils.hex(&data_id)});

    var loaded_file = try database.get(data_id);
    try std.testing.expectEqualSlices(u8, loaded, loaded_file);
    try std.testing.expectEqualSlices(u8, loaded, loaded_file);
}
