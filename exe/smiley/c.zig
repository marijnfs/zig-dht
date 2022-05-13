pub const c = @cImport({
    @cInclude("notcurses/notcurses.h");
    @cInclude("locale.h");
});

const std = @import("std");
const dht = @import("dht");
const default = dht.default;
const communication = dht.communication;
const utils = dht.utils;
const id_ = dht.id;
const serial = dht.serial;
const ID = dht.ID;
const JobQueue = dht.JobQueue;

var input_thread: std.Thread = undefined;

var nc_context: ?*c.notcurses = undefined;
var nc_plane: ?*c.ncplane = undefined;
var nc_line_plane: ?*c.ncplane = undefined;

var msg_buf = std.ArrayList(u32).init(default.allocator);

const UserState = struct {
    username: []u8 = undefined,
    id: ID = undefined,
    char: u32,
    row: c_int = 0,
    col: c_int = 0,
    msg: ?[]u32 = null,
};

var my_state: UserState = .{ .char = 0x0 };

const DrawJob = union(enum) {
    print: []u8,
    print32: []u32,
    print_msg: struct { user: []u8, msg: []u32 },
    render: bool,

    pub fn work(self: *DrawJob, _: *JobQueue(DrawJob)) !void {
        switch (self.*) {
            .print => |buf| {
                print32(std.mem.bytesAsSlice(u32, @alignCast(4, buf)));
            },
            .print32 => |print| {
                print32(print);
            },
            .print_msg => |msg| {
                print_msg(msg.user, msg.msg);
            },
            .render => {
                render();
            },
        }
    }
};

var job_queue: *JobQueue(DrawJob) = undefined;

const BroadcastMessage = struct { id: ID, username: []u8, msg: ?[]u32, char: u32, row: c_int = 0, col: c_int = 0 };

pub fn init() !void {
    job_queue = try JobQueue(DrawJob).init();
    job_queue.start_job_loop();

    _ = c.setlocale(c.LC_ALL, "en_US.UTF-8");
    _ = c.setlocale(c.LC_CTYPE, "en_US.UTF-8");

    my_state.char = try utils.unicodeToInt32(0x1F601);

    nc_context = c.notcurses_init(null, c.stdout);
    if (nc_context == null)
        return error.NotCursesFailedInit;
    nc_plane = c.notcurses_top(nc_context);
    _ = c.ncplane_set_scrolling(nc_plane, 0);

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

pub fn update_user(state: UserState) !void {
    try user_states.put(state.id, state);
    try job_queue.enqueue(.{ .render = true });
}

var user_states = std.AutoHashMap(ID, UserState).init(default.allocator);

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
    my_state.id = default.server.id;
    try update_user(my_state);

    const msg = BroadcastMessage{
        .id = my_state.id,
        .char = my_state.char,
        .row = my_state.row,
        .col = my_state.col,
        .username = try default.allocator.dupe(u8, default.server.config.username),
        .msg = blk: {
            if (my_state.msg) |msg| {
                break :blk try default.allocator.dupe(u32, msg);
            } else {
                break :blk null;
            }
        },
    };
    const content = communication.Content{
        .broadcast = try serial.serialise(msg),
    };
    const envelope = communication.Envelope{
        .source_id = default.server.id,
        .nonce = id_.get_guid(),
        .content = content,
    };

    try default.server.job_queue.enqueue(.{ .broadcast = envelope });
    try job_queue.enqueue(.{ .render = true });
}

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
        const ecg = c.notcurses_get_blocking(nc_context, &input);
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
                try job_queue.enqueue(.{ .print32 = try default.allocator.dupe(u32, msg_buf.items) });
                my_state.msg = try default.allocator.dupe(u32, msg_buf.items);
                try move_char(0, 0);

                try msg_buf.resize(0);

                try job_queue.enqueue(.{ .render = true });
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
            try job_queue.enqueue(.{ .render = true });
        }
    }
}
