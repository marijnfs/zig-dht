const std = @import("std");
const allocator = @import("index.zig").allocator;

pub fn deserialise(comptime T: type, msg: *[]u8) !T {
    var t: T = undefined;
    const info = @typeInfo(T);

    switch (info) {
        .Void => {},
        .Struct => {
            inline for (info.Struct.fields) |*field_info| {
                const name = field_info.name;
                const FieldType = field_info.field_type;

                @field(&t, name) = try deserialise(FieldType, msg);
            }
        },
        .Array => {
            const E = std.meta.Child(T);
            const len = info.Array.len;
            const byteSize = @sizeOf(E) * len;

            if (msg.len < byteSize) {
                return error.MsgSmallerThanArray;
            }

            std.mem.copy(u8, std.mem.asBytes(&t), msg);
            msg = msg[@sizeOf(T)..];
        },
        .Pointer => {
            if (comptime std.meta.trait.isSlice(T)) {
                var len = try deserialise(u64, msg);
                const C = comptime std.meta.Child(T);

                if (len * @sizeOf(C) > msg.len)
                    return error.FailedToDeserialise;

                if (comptime std.meta.sentinel(T) == null) {
                    t = try allocator.alloc(C, len);
                } else {
                    t = try allocator.allocSentinel(C, len, 0);
                }
                for (t) |*e| {
                    e.* = try deserialise(C, msg);
                }
            } else {
                @compileError("Expected to serialise slice");
            }
        },
        .Union => {
            if (comptime info.Union.tag_type) |TagType| {
                const active_tag = try deserialise(TagType, msg);
                inline for (info.Union.fields) |field_info| {
                    if (@field(TagType, field_info.name) == active_tag) {
                        const name = field_info.name;
                        const FieldType = field_info.field_type;
                        t = @unionInit(T, name, try deserialise(FieldType, msg));
                    }
                }
            } else { // c struct or general struct
                const bytes_mem = mem.asBytes(&t);
                if (bytes_mem.len > msg.len)
                    return error.FailedToDeserialise;
                mem.copy(u8, bytes_mem, msg[0..bytes_mem.len]);
                try nng_ret(c.nng_msg_trim(msg, bytes_mem.len));
            }
        },
        .Enum => {
            t = blk: {
                var int_operand = try deserialise(u32, msg);
                break :blk @intToEnum(T, @intCast(std.meta.TagType(T), int_operand));
            };
        },
        .Int, .Float => {
            const bytes_mem = std.mem.asBytes(&t);
            if (bytes_mem.len > msg.len)
                return error.FailedToDeserialise;
            std.mem.copy(u8, bytes_mem, msg.*[0..bytes_mem.len]);

            msg.* = msg.*[bytes_mem.len..];
        },
        .Optional => {
            const C = comptime std.meta.Child(T);
            const opt = try deserialise(u8, msg);
            if (opt > 0) {
                t = try deserialise(C, msg);
            } else {
                t = null;
            }
        },
        else => @compileError("Cannot deserialise " ++ @tagName(@typeInfo(T)) ++ " types (unimplemented)."),
    }
    return t;
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
                try serialise_to_buffer(@as(std.meta.TagType(T), active_tag), buf);

                // This manual inline loop is currently needed to find the right 'field' for the union
                inline for (info.Union.fields) |field_info| {
                    if (@field(TagType, field_info.name) == active_tag) {
                        const name = field_info.name;
                        // const FieldType = field_info.field_type;
                        try serialise_to_buffer(@field(t, name), buf);
                    }
                }
            } else {
                try buf.append(std.mem.asBytes(&t));
            }
        },
        .Enum => {
            try buf.appendSlice(std.mem.asBytes(&t));
        },
        .Int, .Float => {
            try buf.appendSlice(std.mem.asBytes(&t));
        },
        .Optional => {
            if (t == null) {
                const opt: u8 = 0;
                try serialise_to_buffer(opt, buf);
            } else {
                const opt: u8 = 1;
                try serialise_to_buffer(opt, buf);
                try serialise_to_buffer(t.?, buf);
            }
        },
        else => @compileError("Cannot serialise " ++ @tagName(@typeInfo(T)) ++ " types (unimplemented)."),
    }
}

const expect = std.testing.expect;
test "bla" {
    const T = struct {
        a: i64 = 1024,
        b: []i64,
        c: ?i64,
        d: ?i64,
        e: f64 = 6,
    };

    var x = [_]i64{ 1, 2, 3, 4, 5, 6 };
    var t = T{ .b = &x, .c = 42, .d = null };

    var buf = std.ArrayList(u8).init(allocator);
    var msg = serialise_to_buffer(t, &buf);

    std.log.info("{}", .{msg});
    var slice = buf.toOwnedSlice();
    var t2 = try deserialise(T, &slice);
    std.log.info("{}", .{t2});

    try expect(t.a == t2.a);
    try expect(std.mem.eql(i64, t.b, t2.b));
    try expect(t.c.? == t2.c.?);
    try expect(t.d == null);
    try expect(t2.d == null);
    try expect(t.e == t2.e);
}
