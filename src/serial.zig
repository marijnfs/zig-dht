const std = @import("std");

pub fn deserialise(comptime T: type, reader: anytype, allocator: anytype) !T {
    var t: T = undefined;
    const info = @typeInfo(T);

    switch (info) {
        .Void => {},
        .Struct => {
            inline for (info.Struct.fields) |*field_info| {
                const name = field_info.name;
                const FieldType = field_info.field_type;

                @field(&t, name) = try deserialise(FieldType, reader, allocator);
            }
        },
        .Array => {
            try reader.readNoEof(std.mem.asBytes(&t));
        },
        .Pointer => {
            if (comptime std.meta.trait.isSlice(T)) {
                var len = try deserialise(u64, reader, allocator);
                const C = comptime std.meta.Child(T);

                var tmp = if (comptime std.meta.sentinel(T) == null)
                    try allocator.alloc(C, len)
                else
                    try allocator.allocSentinel(C, len, 0);

                for (tmp) |*e| {
                    e.* = try deserialise(C, reader, allocator);
                }
                t = tmp;
            } else {
                @compileError("Expected to serialise slice");
            }
        },
        .Union => {
            if (comptime info.Union.tag_type) |TagType| {
                const active_tag = try deserialise(std.meta.Tag(T), reader, allocator);

                inline for (info.Union.fields) |field_info| {
                    if (@field(TagType, field_info.name) == active_tag) {
                        const name = field_info.name;
                        const FieldType = field_info.field_type;
                        t = @unionInit(T, name, try deserialise(FieldType, reader, allocator));
                    }
                }
            } else { // c struct or general struct
                try reader.readNoEof(std.mem.asBytes(&t));
            }
        },
        .Enum => {
            t = b: {
                var int_operand = try deserialise(u32, reader, allocator);
                break :b @intToEnum(T, @intCast(std.meta.Tag(T), int_operand));
            };
        },
        .Int, .Float => {
            try reader.readNoEof(std.mem.asBytes(&t));
        },
        .Bool => {
            const b = try deserialise(u8, reader, allocator); //use u8 to avoid weird types
            t = b > 0;
        },
        .Optional => {
            const C = comptime std.meta.Child(T);
            const opt = try deserialise(u8, reader, allocator);
            if (opt > 0) {
                t = try deserialise(C, reader, allocator);
            } else {
                t = null;
            }
        },
        else => @compileError("Cannot deserialise " ++ @tagName(@typeInfo(T)) ++ " types (unimplemented)."),
    }
    return t;
}

pub fn serialise(t: anytype, writer: anytype) !void {
    const T = comptime @TypeOf(t);
    const info = @typeInfo(T);

    switch (info) {
        .Void => {},
        .Struct => {
            inline for (info.Struct.fields) |*field_info| {
                const name = field_info.name;
                try serialise(@field(t, name), writer);
            }
        },
        .Array => {
            try writer.writeAll(std.mem.asBytes(&t));
        },
        .Pointer => {
            if (comptime std.meta.trait.isSlice(T)) {
                // const C = std.meta.Child(T);
                try writer.writeAll(std.mem.asBytes(&t.len));

                var i: usize = 0;
                while (i < t.len) : (i += 1) {
                    try serialise(t[i], writer);
                }
            } else {
                @compileError("Expected to serialise slice");
            }
        },
        .Union => {
            if (info.Union.tag_type) |TagType| {
                const active_tag = std.meta.activeTag(t);
                try serialise(@as(std.meta.Tag(T), active_tag), writer);

                // This manual inline loop is currently needed to find the right 'field' for the union
                inline for (info.Union.fields) |field_info| {
                    const name = field_info.name;
                    if (@field(TagType, name) == active_tag) {
                        // const FieldType = field_info.field_type;

                        try serialise(@field(t, name), writer);
                    }
                }
            } else {
                try writer.writeAll(std.mem.asBytes(&t));
            }
        },
        .Enum => {
            try serialise(@intCast(i32, @enumToInt(t)), writer);
        },
        .Int, .Float => {
            try writer.writeAll(std.mem.asBytes(&t));
        },
        .Bool => {
            if (t) {
                try serialise(@intCast(u8, 1), writer);
            } else {
                try serialise(@intCast(u8, 0), writer);
            }
        },
        .Optional => {
            if (t) |t_| {
                const opt: u8 = 1;
                try serialise(opt, writer);
                try serialise(t_, writer);
            } else {
                const opt: u8 = 0;
                try serialise(opt, writer);
            }
        },
        else => @compileError("Cannot serialise " ++ @tagName(@typeInfo(T)) ++ " types (unimplemented)."),
    }
}

pub fn serialise_alloc(t: anytype, alloc: std.mem.Allocator) ![]u8 {
    var array_list = std.ArrayList(u8).init(alloc);
    var writer = array_list.writer();
    try serialise(t, writer);
    return array_list.toOwnedSlice();
}

pub fn deserialise_slice(comptime T: type, slice: []const u8, allocator: anytype) !T {
    var reader = std.io.fixedBufferStream(slice).reader();
    return try deserialise(T, reader, allocator);
}

const expect = std.testing.expect;
test "regular struct" {
    const T = struct {
        a: i64 = 1024,
        b: []i64,
        c: ?i64,
        d: ?i64,
        e: f64 = 6,
        f: bool = true,
        g: bool = false,
    };

    var x = [_]i64{ 1, 2, 3, 4, 5, 6 };
    var t = T{ .b = &x, .c = 42, .d = null };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var slice = try serialise_alloc(t, arena.allocator());
    var t2 = try deserialise_slice(T, slice, arena.allocator());

    try expect(t.a == t2.a);
    try expect(std.mem.eql(i64, t.b, t2.b));
    try expect(t.c.? == t2.c.?);
    try expect(t.d == null);
    try expect(t2.d == null);
    try expect(t.e == t2.e);
    try expect(t.f == t2.f);
    try expect(t.g == t2.g);
}

test "union" {
    const UnionEnum = union(enum) {
        int: i64,
        float: f32,
    };

    var x = UnionEnum{ .int = 32 };
    // var y = UnionEnum{ .float = 42.42 };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var slice = try serialise_alloc(x, arena.allocator());
    defer std.testing.allocator.free(slice);
    var x_2 = try deserialise_slice(UnionEnum, slice, arena.allocator());

    try expect(x.int == x_2.int);
}
