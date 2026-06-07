const std = @import("std");
const posix = std.posix;
const readit = @import("readit.zig"); // made this last year , finally came in use

// define
// #define CTRL_KEY(k) ((k) & 0x1f)
// in C this macro is used to convert a character to its corresponding control character. For example, CTRL_KEY('q') would give the control character for 'q', which is 17 (0x11 in hexadecimal). In Zig, we can achieve the same result with a simple function:
// FIXED: Added 'comptime' so this can be safely evaluated inside the switch pattern matcher

pub const KILO_VERSION = "0.0.1";

const erow = struct {
    chars: []u8,
};

const EditorConfig = struct {
    cx: c_int = 0,
    cy: c_int = 0,
    rowoff: c_int = 0,
    screenrows: c_int = 0,
    screencols: c_int = 0,
    numrows: c_int = 0,
    row: []erow = &[_]erow{}, // an empty slice to start with
    orig_termios: posix.termios,
};

///*** append buffer ***/
// struct abuf {
//   char *b;
//   int len;
// };
// #define ABUF_INIT {NULL, 0}
const abuf = struct {
    b: []u8 = &[_]u8{}, // Starts as an empty, valid slice instead of null

    pub const INIT = abuf{};
};

fn abAppend(allocator: std.mem.Allocator, ab: *abuf, s: []const u8) !void {
    // reallocate dynamically managet the length changes
    const new_mem = allocator.realloc(ab.b, ab.b.len + s.len) catch return;

    // built in slice copying wihtout size matching
    @memcpy(new_mem[ab.b.len..], s);
    // what the above line does is it copies the contents of s into the new memory starting at the position right after the current end of ab.b so taht we can append the new string to the existing buffer without overwriting it.
    ab.b = new_mem;
}

fn abFree(allocator: std.mem.Allocator, ab: *abuf) void {
    allocator.free(ab.b);
    ab.* = abuf.INIT; // Reset to an empty slice after freeing
}

fn ctrlKey(comptime k: u8) u8 {
    return k & 0x1f;
}

fn getCursorPosition(rows: *c_int, cols: *c_int) !c_int {
    // 1. Send the \x1b[6n question to the terminal
    const written = posix.write(posix.STDOUT_FILENO, "\x1b[6n") catch return -1;
    if (written != 4) return -1;

    // 2. Read the response into our bucket array
    var buf = [_]u8{0} ** 32;
    var i: usize = 0;

    while (i < buf.len - 1) {
        const amt = posix.read(posix.STDIN_FILENO, buf[i .. i + 1]) catch break;
        if (amt != 1) break;

        if (buf[i] == 'R') {
            i += 1;
            break;
        }
        i += 1;
    }

    // 3. Make sure the message starts with '\x1b['
    if (buf[0] != '\x1b' or buf[1] != '[') return -1;

    // 4. Split and extract the numbers from the middle (replaces sscanf)
    const payload = buf[2 .. i - 1]; // This isolates the "rows;cols" text part
    var it = std.mem.splitScalar(u8, payload, ';');

    const row_str = it.next() orelse return -1;
    const col_str = it.next() orelse return -1;

    // 5. Convert the text strings into real mathematical integers
    const parsed_row = std.fmt.parseInt(c_int, row_str, 10) catch return -1;
    const parsed_col = std.fmt.parseInt(c_int, col_str, 10) catch return -1;

    // 6. Save the final numbers into your configuration pointers
    rows.* = parsed_row;
    cols.* = parsed_col;
    return 0;
}

fn editorAppendRow(allocator: std.mem.Allocator, s: []const u8) !void {
    const at = @as(usize, @intCast(E.numrows));
    const new_row_count = at + 1;

    const new_rows = try allocator.realloc(E.row, new_row_count);
    E.row = new_rows;

    const chars_copy = try allocator.dupe(u8, s);

    E.row[at] = erow{ .chars = chars_copy };

    E.numrows += 1;
}

fn getWindowSize(rows: *c_int, cols: *c_int) !c_int {
    var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };

    const rc = posix.system.ioctl(posix.STDOUT_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&ws));

    // 1. Check if ioctl failed or returned an empty column width
    if (posix.errno(rc) != .SUCCESS or ws.col == 0) {

        // 2. Fallback: Push cursor to the bottom-right corner
        const written = posix.write(posix.STDOUT_FILENO, "\x1b[999C\x1b[999B") catch return -1;
        if (written != 12) return -1;

        // 3. Ask the terminal where the cursor is and return that instead
        return getCursorPosition(rows, cols);
    } else {
        // 4. Success: Use the values directly from the ioctl struct
        cols.* = ws.col;
        rows.* = ws.row;
        return 0;
    }
}

fn editorOpen(allocator: std.mem.Allocator, filename: []const u8) !void {
    var lines = try readit.readLines(allocator, filename);

    defer lines.deinit();

    for (lines.items) |raw_line| {
        var line = raw_line;

        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }

        try editorAppendRow(allocator, line);
    }
}

// to get size of the terminal
// c tutorial is using struct
//struct editorConfig {
//   struct termios orig_termios;
// };
// struct editorConfig E;

var E: EditorConfig = .{ .orig_termios = undefined };

fn initEditor() !void {
    E.cx = 0;
    E.cy = 0;
    E.rowoff = 0;
    E.numrows = 0;
    E.row = &[_]erow{};

    // Pass pointers directly, just like C
    if (try getWindowSize(&E.screenrows, &E.screencols) == -1) {
        return error.WindowSizeFailed;
    }
}

const editorKey = enum(c_int) { ARROW_LEFT = 1000, ARROW_RIGHT, ARROW_UP, ARROW_DOWN, DEL_KEY, HOME_KEY, END_KEY, PAGE_UP, PAGE_DOWN };

fn editorReadKey() !c_int {
    var c: u8 = 0;
    while (true) {
        const nread = std.io.getStdIn().read(std.mem.asBytes(&c)) catch |err| {
            if (err == error.WouldBlock) continue;
            return err;
        };
        if (nread == 1) break; // CHANGED: breaks instead of returning early
    }

    if (c == '\x1b') {
        var seq = [_]u8{0} ** 3; // FIXED: correct array init

        // FIXED: posix.read now takes proper slices instead of pointers
        const r1 = posix.read(posix.STDIN_FILENO, seq[0..1]) catch return '\x1b';
        if (r1 != 1) return '\x1b';

        const r2 = posix.read(posix.STDIN_FILENO, seq[1..2]) catch return '\x1b';
        if (r2 != 1) return '\x1b';

        if (seq[0] == '[') {
            if (seq[1] >= '0' and seq[1] <= '9') {
                const r3 = posix.read(posix.STDIN_FILENO, seq[2..3]) catch return '\x1b';
                if (r3 != 1) return '\x1b';

                if (seq[2] == '~') {
                    switch (seq[1]) {
                        '1' => return @intFromEnum(editorKey.HOME_KEY),
                        '3' => return @intFromEnum(editorKey.DEL_KEY),
                        '4' => return @intFromEnum(editorKey.END_KEY),
                        '5' => return @intFromEnum(editorKey.PAGE_UP),
                        '6' => return @intFromEnum(editorKey.PAGE_DOWN),
                        '7' => return @intFromEnum(editorKey.HOME_KEY),
                        '8' => return @intFromEnum(editorKey.END_KEY),
                        else => {},
                    }
                }
            } else {
                switch (seq[1]) {
                    'A' => return @intFromEnum(editorKey.ARROW_UP),
                    'B' => return @intFromEnum(editorKey.ARROW_DOWN),
                    'C' => return @intFromEnum(editorKey.ARROW_RIGHT),
                    'D' => return @intFromEnum(editorKey.ARROW_LEFT),
                    'H' => return @intFromEnum(editorKey.HOME_KEY),
                    'F' => return @intFromEnum(editorKey.END_KEY),
                    else => return '\x1b',
                }
            }
        } else if (seq[0] == 'O') {
            switch (seq[1]) {
                'H' => return @intFromEnum(editorKey.HOME_KEY),
                'F' => return @intFromEnum(editorKey.END_KEY),
                else => return '\x1b',
            }
        }
        return '\x1b';
    } else {
        return c;
    }
}

fn editorProcessKeypress() !void {
    const c = try editorReadKey();

    switch (c) {
        ctrlKey('q') => {
            _ = posix.write(posix.STDOUT_FILENO, "\x1b[2J") catch {};
            _ = posix.write(posix.STDOUT_FILENO, "\x1b[H") catch {};
            std.process.exit(0);
        },

        @intFromEnum(editorKey.HOME_KEY) => E.cx = 0,

        @intFromEnum(editorKey.END_KEY) => E.cx = E.screencols - 1,

        @intFromEnum(editorKey.PAGE_UP), @intFromEnum(editorKey.PAGE_DOWN) => {
            var times = E.screenrows;
            while (times > 0) : (times -= 1) {
                const target_key = if (c == @intFromEnum(editorKey.PAGE_UP))
                    @intFromEnum(editorKey.ARROW_UP)
                else
                    @intFromEnum(editorKey.ARROW_DOWN);

                editorMoveCursor(target_key);
            }
        },

        @intFromEnum(editorKey.ARROW_UP), @intFromEnum(editorKey.ARROW_DOWN), @intFromEnum(editorKey.ARROW_LEFT), @intFromEnum(editorKey.ARROW_RIGHT) => {
            editorMoveCursor(c);
        },

        else => {},
    }
}

fn editorRefreshScreen(allocator: std.mem.Allocator) !void {
    try editorScroll();
    var ab = abuf.INIT;
    // clear screen and reposition cursor
    try abAppend(allocator, &ab, "\x1b[?25L");
    try abAppend(allocator, &ab, "\x1b[H");

    // darw the tildeds
    try editorDrawRows(allocator, &ab);

    var buf: [32]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ (E.cy - E.rowoff) + 1, E.cx + 1 });
    try abAppend(allocator, &ab, msg);

    // move cursor back to top left

    try abAppend(allocator, &ab, "\x1b[?25h");

    // output complete buffer to terminal
    _ = posix.write(posix.STDOUT_FILENO, ab.b) catch {};

    // clean up memory allocations
    abFree(allocator, &ab);
}

// TODO
// continue from here : https://viewsourcecode.org/snaptoken/kilo/04.aTextViewer.html#horizontal-scrolling

fn editorMoveCursor(key: c_int) void {
    switch (key) {
        @intFromEnum(editorKey.ARROW_LEFT) => {
            if (E.cx != 0) E.cx -= 1;
        },
        @intFromEnum(editorKey.ARROW_RIGHT) => {
            if (E.cx != E.screencols - 1) E.cx += 1;
        },
        @intFromEnum(editorKey.ARROW_UP) => {
            if (E.cy != 0) E.cy -= 1;
        },
        @intFromEnum(editorKey.ARROW_DOWN) => {
            if (E.cy < E.numrows) E.cy += 1;
        },
        else => {},
    }
}

fn editorScroll() !void {
    if (E.cy < E.rowoff) {
        E.rowoff = E.cy;
    }
    if (E.cy >= E.rowoff + E.screenrows) {
        E.rowoff = E.cy - E.screenrows + 1;
    }
}

fn editorDrawRows(allocator: std.mem.Allocator, ab: *abuf) !void {
    var y: c_int = 0;

    // Loop through every single row row on the screen
    while (y < E.screenrows) : (y += 1) {
        // Calculate the actual row index of the file we are currently rendering
        const filerow: c_int = y + E.rowoff;

        // CASE 1: We are drawing BEYOND the text lines currently loaded in the file
        if (filerow >= E.numrows) {
            // Display the welcome message only if no file rows are loaded at all
            if (E.numrows == 0 and y == @divTrunc(E.screenrows, 3)) {
                var welcome: [80]u8 = undefined;
                const res = try std.fmt.bufPrint(&welcome, "Kilo editor -- version {s}", .{KILO_VERSION});

                var welcomelen = @as(c_int, @intCast(res.len));
                if (welcomelen > E.screencols) welcomelen = E.screencols;

                var padding = @divTrunc(E.screencols - welcomelen, 2);
                if (padding > 0) {
                    try abAppend(allocator, ab, "~");
                    padding -= 1;
                }

                while (padding > 0) : (padding -= 1) {
                    try abAppend(allocator, ab, " ");
                }

                try abAppend(allocator, ab, res[0..@as(usize, @intCast(welcomelen))]);
            } else {
                // Regular trailing line outside the file content gets a tilde
                try abAppend(allocator, ab, "~");
            }
        } else {
            // CASE 2: We are drawing an ACTUAL text line from our loaded buffe
            const current_row = E.row[@as(usize, @intCast(filerow))];

            // Extract the true length of the string from the slice metadata
            var len = @as(c_int, @intCast(current_row.chars.len));
            if (len > E.screencols) len = E.screencols;

            // Slice out the text string up to the screen boundary and push to buffer
            try abAppend(allocator, ab, current_row.chars[0..@as(usize, @intCast(len))]);
        }

        // Clear the remainder of the current line from the cursor to the right margin
        try abAppend(allocator, ab, "\x1b[K");

        // Append a newline carriage return for every row except the absolute last line
        if (y < E.screenrows - 1) {
            try abAppend(allocator, ab, "\r\n");
        }
    }
}

fn die(msg: []const u8, err: anyerror) noreturn {
    // clear screen on exit
    const stdout = std.io.getStdOut().writer();
    // Use 'catch {}' because a noreturn function cannot return an error (!) either
    stdout.writeAll("\x1b[2J") catch {};
    stdout.writeAll("\x1b[H") catch {};
    const stderr = std.io.getStdErr().writer();
    stderr.print("{s}: {s}\n", .{ msg, @errorName(err) }) catch {};
    std.process.exit(1);
}

fn enableRawMode() !posix.termios {
    const orig_termios = posix.tcgetattr(posix.STDIN_FILENO) catch |err| {
        die("tcgetattr", err);
    };

    var raw = orig_termios;

    // Input flags
    raw.iflag.BRKINT = false;
    raw.iflag.ICRNL = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.IXON = false;

    // Output flags
    raw.oflag.OPOST = false;

    // Control flags
    raw.cflag.CSIZE = .CS8;

    // Local flags
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.IEXTEN = false;
    raw.lflag.ISIG = false;

    // Control characters (Timeout & Minimum read bytes)
    raw.cc[@intFromEnum(posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(posix.V.TIME)] = 1;

    posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, raw) catch |err| {
        die("tcsetattr", err);
    };

    // FIXED: Save the values inside your global struct E so disableRawMode can find it!
    E.orig_termios = orig_termios;

    return orig_termios;
}
// this was needed afterall, keeping a sepatarate with defer in each is hard to track.
fn disableRawMode() void {
    // .FLUSH matches C's TCSAFLUSH
    posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, E.orig_termios) catch |err| {
        // If it fails, we pass it to die()
        die("tcsetattr", err);
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // dang gpa here too
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn();

    // fetch cla
    const args = try std.process.argsAlloc(allocator);
    // need to copy in zig cuz copies into safe memory or sum shit
    defer std.process.argsFree(allocator, args); // auto freeing

    _ = try enableRawMode();
    try initEditor();

    if (args.len >= 2) {
        try editorOpen(allocator, args[1]);
    }

    defer disableRawMode();

    while (true) {
        try editorRefreshScreen(allocator);
        try editorProcessKeypress();
    }

    while (true) {
        var c: u8 = 0;
        // Read 1 byte from stdin
        const bytes_read = stdin.read(std.mem.asBytes(&c)) catch |err| {
            if (err == error.WouldBlock) {
                // wouldblock means the read timed out, so we just continue to the next iteration
                continue;
            }
            die("read", err);
        };

        // If no bytes were read (timeout occurred), skip processing
        if (bytes_read == 0) continue;

        // Check if character is a control character
        if (std.ascii.isControl(c)) {
            try stdout.print("{d}\r\n", .{c});
        } else {
            try stdout.print("{d} ('{c}')\r\n", .{ c, c });
        }

        if (c == ctrlKey('x')) break; // ctrl q is the actual close key on my pc it will close my app so i am making it x

    }
}
