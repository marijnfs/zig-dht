const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const ID = index.ID;
const Hash = index.Hash;

const Blob = []const u8;
const MaxBlobSize = 64 << 10; //64KB

pub const Database = struct {
    store: std.AutoHashMap(ID, Blob),
    store_dir: std.fs.Dir,

    pub fn create(path: []const u8) !*Database {
        var db = try default.allocator.create(Database);

        try db.init(path);
        return db;
    }

    pub fn init(db: *Database, path: []const u8) !void {
        db.store = std.AutoHashMap(ID, Blob).init(default.allocator);

        try db.open_directory(path);
    }

    pub fn open_directory(db: *Database, path: []const u8) !void {
        std.fs.cwd().makeDir(path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        db.store_dir = try std.fs.cwd().openDir(path, .{ .iterate = true, .no_follow = true });
    }

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
