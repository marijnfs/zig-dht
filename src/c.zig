pub const c = @cImport({
    @cInclude("notcurses/notcurses.h");
    @cInclude("locale.h");
});

const std = @import("std");
const index = @import("index.zig");
const default = index.default;

var input_thread: std.Thread = undefined;

var nc_context: ?*c.notcurses = undefined;
var nc_plane: ?*c.ncplane = undefined;

pub fn print(str: []u8) void {
    for (str) |char| {
        _ = c.ncplane_putchar(nc_plane, char);
    }
    _ = c.notcurses_render(nc_context);
}

pub fn read_loop() !void {
    while (true) {
        var input: c.ncinput = undefined;
        const char = c.notcurses_getc_blocking(nc_context, &input);
        const data = try std.fmt.allocPrint(default.allocator, "{} {}", .{ char, input.id });
        print(data);
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
