pub const c = @cImport({
    @cInclude("notcurses/notcurses.h");
    @cInclude("locale.h");
});

const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;

var input_thread: std.Thread = undefined;

var nc_context: ?*c.notcurses = undefined;
var nc_plane: ?*c.ncplane = undefined;

pub fn print(str: []u8) void {
    for (str) |char| {
        _ = c.ncplane_putchar(nc_plane, char);
    }
    _ = c.notcurses_render(nc_context);
}

pub fn print32(str: []u32) void {
    var cell: c.nccell = undefined;
    c.nccell_init(&cell);
    for (str) |ecg| {
        _ = c.nccell_load_egc32(nc_plane, &cell, ecg);
        _ = c.ncplane_putc(nc_plane, &cell);
    }

    _ = c.notcurses_render(nc_context);
}

pub fn read_loop() !void {
    var buf = std.ArrayList(u32).init(default.allocator);
    while (true) {
        var input: c.ncinput = undefined;
        const ecg = c.notcurses_getc_blocking(nc_context, &input);
        // const data = try std.fmt.allocPrint(default.allocator, "{} {}", .{ char, input.id });
        if (input.id == c.NCKEY_ENTER) {
            try jobs.enqueue(.{ .print32 = try std.mem.dupe(default.allocator, u32, buf.items) });
            try buf.resize(0);
        } else {
            try buf.append(ecg);
        }
    }
}

pub fn init() !void {
    nc_context = c.notcurses_init(null, c.stdout);
    nc_plane = c.notcurses_top(nc_context);
    _ = c.ncplane_set_scrolling(nc_plane, true);

    input_thread = try std.Thread.spawn(.{}, read_loop, .{});
}

pub fn deinit() void {
    _ = c.notcurses_stop(nc_context);
}
