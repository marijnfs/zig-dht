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

pub fn print_msg(user: []u8, msg: []u32) void {
    for (user) |char| {
        _ = c.ncplane_putchar_stained(nc_plane, char);
    }
    _ = c.ncplane_putchar_stained(nc_plane, ':');
    _ = c.ncplane_putchar_stained(nc_plane, ' ');

    var cell: c.nccell = undefined;
    c.nccell_init(&cell);
    for (msg) |ecg| {
        _ = c.nccell_load_egc32(nc_plane, &cell, ecg);
        _ = c.ncplane_putc(nc_plane, &cell);
    }
    _ = c.ncplane_putchar(nc_plane, '\n');
    _ = c.notcurses_render(nc_context);
}

pub fn print_bottomline() !void {
    // var cell: c.nccell = undefined;
    // c.nccell_init(&cell);
    // _ = c.nccell_set_fg_rgb8(&cell, 230, 100, 50);
    // _ = c.ncplane_set_base_cell(nc_line_plane, &cell);

    var cell = get_cell();
    const username = default.server.config.username;
    for (username) |char| {
        // nccell_set_fg_rgb8
        _ = c.nccell_load_char(nc_line_plane, &cell, char);
        _ = c.nccell_set_fg_rgb8(&cell, 230, 100, 50);
        _ = c.ncplane_putc(nc_line_plane, &cell);
        // _ = c.ncplane_putchar_stained(nc_line_plane, char);
    }
    _ = c.ncplane_putchar(nc_line_plane, ':');
    _ = c.ncplane_putchar(nc_line_plane, ' ');

    for (msg_buf.items) |ecg| {
        _ = c.nccell_load_egc32(nc_line_plane, &cell, ecg);
        _ = c.ncplane_putc(nc_line_plane, &cell);
    }
}

pub fn get_cell() c.nccell {
    var cell: c.nccell = undefined;
    c.nccell_init(&cell);
    return cell;
}

pub fn draw_character(plane: ?*c.ncplane, char: u32, text_: ?[]u32, row: c_int, col: c_int) void {
    // var x: c_int = 0;
    // var y: c_int = 0;

    // _ = c.ncplane_dim_yx(plane, &y, &x);

    var cell = get_cell();

    _ = c.nccell_load_egc32(plane, &cell, char);
    _ = c.nccell_set_fg_rgb8(&cell, 230, 100, 50);

    const move_status = c.ncplane_cursor_move_yx(plane, row, col);
    if (move_status == -1)
        return;
    _ = c.ncplane_putc(plane, &cell);

    if (text_) |text| {
        _ = c.ncplane_putchar(plane, ' ');
        for (text) |ch| {
            _ = c.nccell_load_egc32(plane, &cell, ch);
            _ = c.ncplane_putc(plane, &cell);
        }
    }
    //

}

pub fn move_char(drow: c_int, dcol: c_int) !void {
    my_state.row += drow;
    my_state.col += dcol;

    const content = communication.Content{ .broadcast = .{
        .char = my_state.char,
        .row = my_state.row,
        .col = my_state.col,
        .user = try std.mem.dupe(default.allocator, u8, default.server.config.username),
        .msg = blk: {
            if (my_state.msg) |msg| {
                break :blk try std.mem.dupe(default.allocator, u32, msg);
            } else {
                break :blk null;
            }
        },
    } };
    const message = communication.Message{ .source_id = default.server.id, .nonce = utils.get_guid(), .content = content };

    try update_user(default.server.config.username, my_state);
    try jobs.enqueue(.{ .broadcast = message });
    try jobs.enqueue(.{ .render = true });
}

var msg_buf = std.ArrayList(u32).init(default.allocator);

const UserState = struct {
    char: u32,
    row: c_int = 0,
    col: c_int = 0,
    msg: ?[]u32 = null,
};

var my_state: UserState = .{ .char = 0xb58c9FF0 }; //0x42 };

pub fn update_user(user: []u8, state: UserState) !void {
    try user_states.put(user, state);
    try jobs.enqueue(.{ .render = true });
}

var user_states = std.StringArrayHashMap(UserState).init(default.allocator);
pub fn render() void {
    // draw base
    c.ncplane_erase(nc_line_plane);
    c.ncplane_home(nc_line_plane);
    try print_bottomline();

    _ = c.notcurses_render(nc_context);

    // Draw main plane
    c.ncplane_erase(nc_plane);
    draw_character(nc_plane, my_state.char, my_state.msg, my_state.row, my_state.col);

    var it = user_states.iterator();
    while (it.next()) |kv| {
        // const username = kv.key_ptr.*;
        const state = kv.value_ptr.*;
        draw_character(nc_plane, state.char, state.msg, state.row, state.col);
    }
    _ = c.notcurses_render(nc_context);
}

pub fn read_loop() !void {
    while (true) {
        var input: c.ncinput = undefined;
        const ecg = c.notcurses_getc_blocking(nc_context, &input);
        // const data = try std.fmt.allocPrint(default.allocator, "{} {}", .{ char, input.id });
        if (input.id > 0x100000) { //NC_KEY
            if (input.id == c.NCKEY_RESIZE) {
                _ = c.notcurses_render(nc_context);
            } else if (input.id == c.NCKEY_BACKSPACE or input.id == c.NCKEY_DEL) {
                if (msg_buf.items.len > 0) {
                    _ = msg_buf.swapRemove(msg_buf.items.len - 1);
                    _ = c.notcurses_render(nc_context);
                }
            } else if (input.id == c.NCKEY_ENTER) {
                try jobs.enqueue(.{ .print32 = try std.mem.dupe(default.allocator, u32, msg_buf.items) });
                my_state.msg = try std.mem.dupe(default.allocator, u32, msg_buf.items);
                try move_char(0, 0);

                try msg_buf.resize(0);

                try jobs.enqueue(.{ .render = true });
            } else if (input.id == c.NCKEY_UP) {
                try move_char(-1, 0);
            } else if (input.id == c.NCKEY_DOWN) {
                try move_char(1, 0);
            } else if (input.id == c.NCKEY_LEFT) {
                try move_char(0, -1);
            } else if (input.id == c.NCKEY_RIGHT) {
                try move_char(0, 1);
            }
        } else {
            try msg_buf.append(ecg);
            try jobs.enqueue(.{ .render = true });
        }
    }
}

pub fn init() !void {
    _ = c.setlocale(c.LC_ALL, "en_US.UTF-8");
    _ = c.setlocale(c.LC_CTYPE, "en_US.UTF-8");

    nc_context = c.notcurses_init(null, c.stdout);
    if (nc_context == null)
        return error.NotCursesFailedInit;
    nc_plane = c.notcurses_top(nc_context);
    _ = c.ncplane_set_scrolling(nc_plane, false);

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
