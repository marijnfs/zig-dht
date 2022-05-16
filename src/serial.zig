const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const communication = index.communication;
const utils = index.utils;

const ID = index.ID;

pub fn deserialise(comptime T: type, msg_ptr: *[]const u8) !T {
    const msg = msg_ptr.*;
    var t: T = undefined;
    const info = @typeInfo(T);

    switch (info) {
        .Void => {},
        .Struct => {
            inline for (info.Struct.fields) |*field_info| {
                const name = field_info.name;
                const FieldType = field_info.field_type;

                @field(&t, name) = try deserialise(FieldType, msg_ptr);
            }
        },
        .Array => {
            const byteSize = @sizeOf(T);

            if (msg.len < byteSize) {
                return error.MsgSmallerThanArray;
            }
            std.mem.copy(u8, std.mem.asBytes(&t), msg[0..byteSize]);
            msg_ptr.* = msg[byteSize..];
        },
        .Pointer => {
            if (comptime std.meta.trait.isSlice(T)) {
                var len = try deserialise(u64, msg_ptr);
                const C = comptime std.meta.Child(T);

                if (len * @sizeOf(C) > msg.len)
                    return error.FailedToDeserialise;

                var tmp = if (comptime std.meta.sentinel(T) == null)
                    try default.allocator.alloc(C, len)
                else
                    try default.allocator.allocSentinel(C, len, 0);

                for (tmp) |*e| {
                    e.* = try deserialise(C, msg_ptr);
                }
                t = tmp;
            } else {
                @compileError("Expected to serialise slice");
            }
        },
        .Union => {
            if (comptime info.Union.tag_type) |TagType| {
                const active_tag = try deserialise(std.meta.Tag(T), msg_ptr);

                inline for (info.Union.fields) |field_info| {
                    if (@field(TagType, field_info.name) == active_tag) {
                        const name = field_info.name;
                        const FieldType = field_info.field_type;
                        t = @unionInit(T, name, try deserialise(FieldType, msg_ptr));
                    }
                }
            } else { // c struct or general struct
                const bytes_mem = std.mem.asBytes(&t);
                if (bytes_mem.len > msg.len)
                    return error.FailedToDeserialise;
                std.mem.copy(u8, bytes_mem, msg[0..bytes_mem.len]);
                msg_ptr.* = msg[bytes_mem.len..];
            }
        },
        .Enum => {
            t = blk: {
                var int_operand = try deserialise(u32, msg_ptr);
                break :blk @intToEnum(T, @intCast(std.meta.Tag(T), int_operand));
            };
        },
        .Int, .Float => {
            const bytes_mem = std.mem.asBytes(&t);
            if (bytes_mem.len > msg.len)
                return error.FailedToDeserialise;
            std.mem.copy(u8, bytes_mem, msg[0..bytes_mem.len]);
            msg_ptr.* = msg[bytes_mem.len..];
        },
        .Optional => {
            const C = comptime std.meta.Child(T);
            const opt = try deserialise(u8, msg_ptr);
            if (opt > 0) {
                t = try deserialise(C, msg_ptr);
            } else {
                t = null;
            }
        },
        else => @compileError("Cannot deserialise " ++ @tagName(@typeInfo(T)) ++ " types (unimplemented)."),
    }
    return t;
}

pub fn serialise(t: anytype) ![]const u8 {
    var buf = std.ArrayList(u8).init(default.allocator);
    try serialise_to_buffer(t, &buf);
    return buf.toOwnedSlice();
}

pub fn serialise_to_buffer(t: anytype, buf: *std.ArrayList(u8)) !void {
    const T = comptime @TypeOf(t);

    const info = @typeInfo(T);
    switch (info) {
        .Void => {},
        .Struct => {
            inline for (info.Struct.fields) |*field_info| {
                const name = field_info.name;
                // const FieldType = field_info.field_type;
                try serialise_to_buffer(@field(t, name), buf);
            }
        },
        .Array => {
            // const len = info.Array.len;
            try buf.appendSlice(std.mem.asBytes(&t));
        },
        .Pointer => {
            if (comptime std.meta.trait.isSlice(T)) {
                // const C = std.meta.Child(T);
                try buf.appendSlice(std.mem.asBytes(&t.len));

                var i: usize = 0;
                while (i < t.len) : (i += 1) {
                    try serialise_to_buffer(t[i], buf);
                }
            } else {
                @compileError("Expected to serialise slice");
            }
        },
        .Union => {
            if (info.Union.tag_type) |TagType| {
                const active_tag = std.meta.activeTag(t);
                try serialise_to_buffer(@as(std.meta.Tag(T), active_tag), buf);

                // This manual inline loop is currently needed to find the right 'field' for the union
                inline for (info.Union.fields) |field_info| {
                    const name = field_info.name;
                    if (@field(TagType, name) == active_tag) {
                        // const FieldType = field_info.field_type;

                        try serialise_to_buffer(@field(t, name), buf);
                    }
                }
            } else {
                try buf.appendSlice(std.mem.asBytes(&t));
            }
        },
        .Enum => {
            try serialise_to_buffer(@intCast(i32, @enumToInt(t)), buf);
        },
        .Int, .Float => {
            try buf.appendSlice(std.mem.asBytes(&t));
        },
        .Optional => {
            if (t) |t_| {
                const opt: u8 = 1;
                try serialise_to_buffer(opt, buf);
                try serialise_to_buffer(t_, buf);
            } else {
                const opt: u8 = 0;
                try serialise_to_buffer(opt, buf);
            }
        },
        else => @compileError("Cannot serialise " ++ @tagName(@typeInfo(T)) ++ " types (unimplemented)."),
    }
}

const expect = std.testing.expect;
test "regular struct" {
    const T = struct {
        a: i64 = 1024,
        b: []i64,
        c: ?i64,
        d: ?i64,
        e: f64 = 6,
    };

    var x = [_]i64{ 1, 2, 3, 4, 5, 6 };
    var t = T{ .b = &x, .c = 42, .d = null };

    var slice = try serialise(t);
    var t2 = try deserialise(T, &slice);

    try expect(t.a == t2.a);
    try expect(std.mem.eql(i64, t.b, t2.b));
    try expect(t.c.? == t2.c.?);
    try expect(t.d == null);
    try expect(t2.d == null);
    try expect(t.e == t2.e);
}

test "union" {
    const UnionEnum = union(enum) {
        int: i64,
        float: f32,
    };

    var x = UnionEnum{ .int = 32 };
    // var y = UnionEnum{ .float = 42.42 };

    var slice = try serialise(x);
    var x_2 = try deserialise(UnionEnum, &slice);

    try expect(x.int == x_2.int);
}

test "message" {
    const envelope = communication.Envelope{
        .content = .{
            .broadcast = "test",
        },
    };

    const slice = try serialise(envelope);
    var tmp_slice = slice;
    var x_2 = try deserialise(communication.Envelope, &tmp_slice);
    const slice2 = try serialise(x_2);
    try expect(std.mem.eql(u8, slice2, slice));
}
