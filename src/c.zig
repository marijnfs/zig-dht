pub const c = @cImport({
    @cInclude("notcurses/notcurses.h");
    @cInclude("locale.h");
});

const std = @import("std");
const index = @import("index.zig");
const default = index.default;
const jobs = index.jobs;
const communication = index.communication;
const utils = index.utils;

var input_thread: std.Thread = undefined;

var nc_context: ?*c.notcurses = undefined;
var nc_plane: ?*c.ncplane = undefined;
var nc_line_plane: ?*c.ncplane = undefined;

pub fn print(str: []u8) void {
    for (str) |char| {
        _ = c.ncplane_putchar_stained(nc_plane, char);
    }
    _ = c.ncplane_putchar_stained(nc_plane, '\n');
    _ = c.notcurses_render(nc_context);
}

pub fn print32(str: []u32) void {
    var cell: c.nccell = undefined;
    c.nccell_init(&cell);
    for (str) |ecg| {
        _ = c.nccell_load_egc32(nc_plane, &cell, ecg);
        _ = c.ncplane_putc(nc_plane, &cell);
    }
    _ = c.ncplane_putchar_stained(nc_plane, '\n');
    _ = c.notcurses_render(nc_context);
}

pub fn print_username() !void {
    // var cell: c.nccell = undefined;
    // c.nccell_init(&cell);
    // _ = c.nccell_set_fg_rgb8(&cell, 230, 100, 50);
    // _ = c.ncplane_set_base_cell(nc_line_plane, &cell);

    var other_cell: c.nccell = undefined;
    const username = default.server.config.username;
    for (username) |char| {
        // nccell_set_fg_rgb8
        _ = c.nccell_load_char(nc_line_plane, &other_cell, char);
        _ = c.nccell_set_fg_rgb8(&other_cell, 230, 100, 50);
        _ = c.ncplane_putc(nc_line_plane, &other_cell);
        // _ = c.ncplane_putchar_stained(nc_line_plane, char);
    }
    _ = c.ncplane_putchar(nc_line_plane, ':');
    _ = c.ncplane_putchar(nc_line_plane, ' ');

    _ = c.nccell_set_fg_rgb8(&other_cell, 50, 50, 50);
}

pub fn read_loop() !void {
    var buf = std.ArrayList(u32).init(default.allocator);
    while (true) {
        var input: c.ncinput = undefined;
        const ecg = c.notcurses_getc_blocking(nc_context, &input);
        // const data = try std.fmt.allocPrint(default.allocator, "{} {}", .{ char, input.id });
        if (input.id > 0x100000) { //NC_KEY
            if (input.id == c.NCKEY_RESIZE) {
                _ = c.notcurses_render(nc_context);
            } else if (input.id == c.NCKEY_ENTER) {
                try jobs.enqueue(.{ .print32 = try std.mem.dupe(default.allocator, u32, buf.items) });

                const content = communication.Content{ .broadcast = try std.mem.dupe(default.allocator, u8, std.mem.sliceAsBytes(buf.items)) };
                const message = communication.Message{ .source_id = default.server.id, .nonce = utils.get_guid(), .content = content };

                try jobs.enqueue(.{ .broadcast = message });

                try buf.resize(0);

                c.ncplane_erase(nc_line_plane);
                c.ncplane_home(nc_line_plane);
                try print_username();

                _ = c.notcurses_render(nc_context);
            }
        } else {
            try buf.append(ecg);

            var cell: c.nccell = undefined;
            c.nccell_init(&cell);
            _ = c.nccell_load_egc32(nc_line_plane, &cell, ecg);
            _ = c.ncplane_putc(nc_line_plane, &cell);

            _ = c.notcurses_render(nc_context);
        }
    }
}

pub fn init() !void {
    nc_context = c.notcurses_init(null, c.stdout);
    if (nc_context == null)
        return error.NotCursesFailedInit;
    nc_plane = c.notcurses_top(nc_context);
    _ = c.ncplane_set_scrolling(nc_plane, true);

    var plane_options = std.mem.zeroes(c.ncplane_options);
    plane_options.y = c.NCALIGN_BOTTOM;
    plane_options.x = c.NCALIGN_LEFT;
    plane_options.rows = 1;
    plane_options.cols = 80;
    plane_options.flags = c.NCPLANE_OPTION_HORALIGNED | c.NCPLANE_OPTION_VERALIGNED | c.NCPLANE_OPTION_FIXED;
    nc_line_plane = c.ncplane_create(nc_plane, &plane_options);

    input_thread = try std.Thread.spawn(.{}, read_loop, .{});
}

pub fn deinit() void {
    _ = c.notcurses_stop(nc_context);
}
