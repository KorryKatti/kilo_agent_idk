const std = @import("std");
const posix = std.posix;

// define
// #define CTRL_KEY(k) ((k) & 0x1f)
// in C this macro is used to convert a character to its corresponding control character. For example, CTRL_KEY('q') would give the control character for 'q', which is 17 (0x11 in hexadecimal). In Zig, we can achieve the same result with a simple function:
// FIXED: Added 'comptime' so this can be safely evaluated inside the switch pattern matcher


const EditorConfig = struct {
    screenrows:c_int = 0,
    screencols:c_int = 0,
    orig_termios: posix.termios,
};

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

// to get size of the terminal
// c tutorial is using struct 
//struct editorConfig {
//   struct termios orig_termios;
// };
// struct editorConfig E;


var E: EditorConfig = .{ .orig_termios = undefined };

fn initEditor() !void {
    //   if (getWindowSize(&E.screenrows, &E.screencols) == -1) die("getWindowSize");
    const rows_ptr = &E.screenrows;
    const cols_ptr = &E.screencols;
    if (try getWindowSize(rows_ptr, cols_ptr) == -1) {
        die("getWindowSize", error.GenericError);
    }
}

fn editorReadKey() !u8 {
    var c:u8=0;
    while (true){
        const nread = std.io.getStdIn().read(std.mem.asBytes(&c)) catch |err| {
            if (err == error.WouldBlock) {
                continue;
            }
            return err;
        };
        if (nread==1){
            return c;
        }
    }
}

fn editorProcessKeypress() !void {
    const c = try editorReadKey();
    switch (c) {
        ctrlKey('x') => {
            const stdout = std.io.getStdOut().writer();
            // Clear the screen before exiting
            try stdout.writeAll("\x1b[2J");
            try stdout.writeAll("\x1b[H");
            // Exit the editor
            std.process.exit(0);
        },
        else => {
            // For now, we just print the key code
            const stdout = std.io.getStdOut().writer();
            try stdout.print("Key pressed: {d}\r\n", .{c});
        }
    }
}

fn editorRefreshScreen() !void {
    const stdout = std.io.getStdOut().writer();
    
    // Clear the screen (Sends exactly the 4 bytes: \x1b, [, 2, J)
    try stdout.writeAll("\x1b[2J");
    
    // Move the cursor to the top-left corner (Sends 3 bytes: \x1b, [, H)
    try stdout.writeAll("\x1b[H");

    try editorDrawRows();
    stdout.writeAll("\x1b[H") catch {};// this moves the cursor back to the top-left corner after drawing the rows, so that the user can start typing from there
}

// TODO:
// continue from here : https://viewsourcecode.org/snaptoken/kilo/03.rawInputAndOutput.html#append-buffer

fn editorDrawRows() !void {
    var i:i32 = 0;
    while (i < E.screenrows) {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll("~");
        try stdout.writeAll("~\r\n");
        i += 1;
        // makes tildes on lhs of screen like vim
    }
}

fn die(msg: []const u8, err:anyerror) noreturn {
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
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn();

    _ = try enableRawMode();
    try initEditor();

    defer disableRawMode();

    while (true){
        try editorRefreshScreen();
        try editorProcessKeypress();
    }

    while (true) {
        var c: u8 = 0;
        // Read 1 byte from stdin
        const bytes_read = stdin.read(std.mem.asBytes(&c)) catch |err| {
            if (err==error.WouldBlock){
                // wouldblock means the read timed out, so we just continue to the next iteration
                continue;
            }
            die("read",err);
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
