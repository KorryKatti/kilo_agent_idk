// /* Kilo -- A very simple editor in less than 1-kilo lines of code (as counted
//  *         by "cloc"). Does not depend on libcurses, directly emits VT100
//  *         escapes on the terminal.
//  *
//  * -----------------------------------------------------------------------
//  *
//  * Copyright (C) 2016 Salvatore Sanfilippo <antirez at gmail dot com>
//  *
//  * All rights reserved.
//  *
//  * Redistribution and use in source and binary forms, with or without
//  * modification, are permitted provided that the following conditions are
//  * met:
//  *
//  *  *  Redistributions of source code must retain the above copyright
//  *     notice, this list of conditions and the following disclaimer.
//  *
//  *  *  Redistributions in binary form must reproduce the above copyright
//  *     notice, this list of conditions and the following disclaimer in the
//  *     documentation and/or other materials provided with the distribution.
//  *
//  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//  * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//  */

const std = @import("std");
const posix = std.posix;
const readit = @import("readit.zig"); // made this last year , finally came in use

// define
// #define CTRL_KEY(k) ((k) & 0x1f)
// in C this macro is used to convert a character to its corresponding control character. For example, CTRL_KEY('q') would give the control character for 'q', which is 17 (0x11 in hexadecimal). In Zig, we can achieve the same result with a simple function:
// FIXED: Added 'comptime' so this can be safely evaluated inside the switch pattern matcher

pub const KILO_VERSION = "0.0.1";
pub const KILO_TAB_STOP: c_int = 8;
pub const KILO_QUIT_TIMES: c_int = 3;

const erow = struct {
    chars: []u8,
    size: c_int,
    rsize: c_int,
    render: []u8,
};

const EditorConfig = struct {
    cx: c_int = 0,
    cy: c_int = 0,
    rowoff: c_int = 0,
    coloff: c_int = 0,
    rx: c_int = 0,
    filename: ?[]u8 = null,
    screenrows: c_int = 0,
    screencols: c_int = 0,
    dirty: c_int = 0,
    numrows: c_int = 0,
    row: []erow = &[_]erow{}, // an empty slice to start with
    statusmsg: [80]u8 = [_]u8{0} ** 80,
    statusmsg_time: i64 = 0,
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

fn editorUpdateRow(allocator: std.mem.Allocator, row: *erow) !void {
    allocator.free(row.render);
    const tabs = std.mem.count(u8, row.chars, "\t");

    const tab_size = @as(usize, @intCast(KILO_TAB_STOP));

    row.render = try allocator.alloc(u8, row.chars.len + (tabs * (tab_size - 1)));

    // fill the new buffer and pad tabs out to trab stops
    var idx: usize = 0;
    for (row.chars) |c| {
        if (c == '\t') {
            row.render[idx] = ' ';
            idx += 1;
            while (idx % tab_size != 0) : (idx += 1) {
                row.render[idx] = ' ';
            }
        } else {
            row.render[idx] = c;
            idx += 1;
        }
    }
    // match final index count to row rendered ssize
    row.rsize = @intCast(idx);
}

// insert single character into row at given position
// if out of boudns append to end of row
fn editorRowInsertChar(allocator: std.mem.Allocator, row: *erow, at: c_int, c: u8) !void {
    // clamp insertion point to validate range
    var insert_pos = at;
    if (insert_pos < 0 or insert_pos > row.size) {
        insert_pos = row.size;
    }

    const pos = @as(usize, @intCast(insert_pos));
    const current_size = @as(usize, @intCast(row.size));

    // reallocate +1 for new char , +1 for null terminator
    const new_chars = try allocator.realloc(row.chars, current_size + 2);

    // shift everything from insert_pos onward one byte to the right
    const src = new_chars[pos .. current_size + 1]; // +1 to include existing null if present
    const dst = new_chars[pos + 1 .. current_size + 2];
    std.mem.copyForwards(u8, dst, src);

    // insert new character
    new_chars[pos] = c;

    // update row metadata
    row.chars = new_chars;
    row.size += 1;

    // rebuild rendered version
    try editorUpdateRow(allocator, row); // crazy how much things goes to insert a character man damn
    E.dirty += 1;
}

/// Handles the Enter key: splits the current line or inserts an empty line.
fn editorInsertNewline(allocator: std.mem.Allocator) !void {
    // If cursor is at the start of the line, insert an empty line above
    if (E.cx == 0) {
        try editorInsertRow(allocator, E.cy, "");
    } else {
        // Cursor is in the middle or end of the line — split it
        const row_index = @as(usize, @intCast(E.cy));
        const row = &E.row[row_index];

        // Get the text after the cursor: this becomes the new line
        const split_pos = @as(usize, @intCast(E.cx));
        const remaining = row.chars[split_pos..@as(usize, @intCast(row.size))];

        // Insert a new row below with the remaining text
        try editorInsertRow(allocator, E.cy + 1, remaining);

        // Truncate current row to keep only text before cursor
        // Realloc to shrink buffer and add null terminator
        const new_chars = try allocator.realloc(row.chars, split_pos + 1);
        row.chars = new_chars;
        row.size = E.cx;
        row.chars[@as(usize, @intCast(row.size))] = 0;

        // Rebuild rendered version of the truncated row
        try editorUpdateRow(allocator, row);
    }

    // Move cursor to the start of the newly created line
    E.cy += 1;
    E.cx = 0;
}

// simple backspaces
/// Deletes a single character from a row at the given position.
/// Shifts all characters after `at` one position left to close the gap.
fn editorRowDelChar(allocator: std.mem.Allocator, row: *erow, at: c_int) void {
    // Guard: can't delete before start or past end of row
    if (at < 0 or at >= row.size) {
        return;
    }

    const pos = @as(usize, @intCast(at));
    const current_size = @as(usize, @intCast(row.size));

    // Shift everything from pos+1 leftward by one byte
    // This overwrites the char at `pos` with the char at `pos+1`
    const src = row.chars[pos + 1 .. current_size];
    const dst = row.chars[pos .. current_size - 1];
    std.mem.copyForwards(u8, dst, src);

    // Shrink the allocation to match new size
    const new_chars = allocator.realloc(row.chars, current_size - 1) catch row.chars[0 .. current_size - 1];
    row.chars = new_chars;

    // Update row metadata
    row.size -= 1;

    // Rebuild rendered version (tabs expanded, etc.)
    editorUpdateRow(allocator, row) catch {};

    // Mark buffer as modified (any non-zero means dirty)
    E.dirty += 1;
}

/// Frees all heap-allocated memory owned by a single row.
fn editorFreeRow(allocator: std.mem.Allocator, row: *erow) void {
    // Free the tab-expanded render buffer
    allocator.free(row.render);

    // Free the raw character buffer
    allocator.free(row.chars);
}

/// Deletes an entire row from the editor, shifting all rows below it up.
fn editorDelRow(allocator: std.mem.Allocator, at: c_int) void {
    // Guard: row index must be within valid bounds
    if (at < 0 or at >= E.numrows) {
        return;
    }

    const pos = @as(usize, @intCast(at));
    const numrows = @as(usize, @intCast(E.numrows));

    // Free the row's allocated memory before overwriting it
    editorFreeRow(allocator, &E.row[pos]);

    // Shift all rows after `at` up by one position to close the gap
    // This overwrites the deleted row with the one below it
    const src = E.row[pos + 1 .. numrows];
    const dst = E.row[pos .. numrows - 1];
    std.mem.copyForwards(erow, dst, src);

    // Shrink the row array to match new count
    const new_rows = allocator.realloc(E.row, numrows - 1) catch E.row[0 .. numrows - 1];
    E.row = new_rows;

    // Update editor state
    E.numrows -= 1;
    E.dirty += 1;
}

/// Deletes the character to the left of the cursor (backspace behavior).
/// If cursor is at the start of a line, this currently does nothing.
fn editorDelChar(allocator: std.mem.Allocator) !void {
    // Can't delete if cursor is past the last row (on the tilde lines)
    if (E.cy == E.numrows) {
        return;
    }
    if (E.cx == 0 and E.cy == 0) {
        return;
    }

    const row_index = @as(usize, @intCast(E.cy));
    const row = &E.row[row_index];

    // Only delete if there's a character to the left of the cursor
    if (E.cx > 0) {
        // Delete the character at cx - 1 (one position left of cursor)
        editorRowDelChar(allocator, row, E.cx - 1);

        // Move cursor left to fill the gap
        E.cx -= 1;
    } else {
        E.cx = E.row[@intCast(E.cy - 1)].size;
        try editorRowAppendString(allocator, &E.row[@intCast(E.cy - 1)], row.chars);
        editorDelRow(allocator, E.cy);
        E.cy -= 1;
    }
}

// append a string to the end of rows character buffer
// i am gonna stop pretending i even understand half of the thing i am doing
fn editorRowAppendString(allocator: std.mem.Allocator, row: *erow, s: []const u8) !void {
    const current_size = @as(usize, @intCast(row.size));
    const append_len = s.len;

    // grow the buffer : current size + new tex
    const new_chars = try allocator.realloc(row.chars, current_size + append_len + 1);
    row.chars = new_chars;

    // copy new string at end of existing content
    @memcpy(row.chars[current_size .. current_size + append_len], s);

    // update size and add null termination , idk if we need this in zig ??
    row.size += @as(c_int, @intCast(append_len));
    row.chars[@as(usize, @intCast(row.size))] = 0;

    // rebuild rendered version
    try editorUpdateRow(allocator, row);

    // modified
    E.dirty += 1;
}

// insert character at current cursor positions
// if cursor on new line past the end of file , create enmpty road first
fn editorInsertChar(allocator: std.mem.Allocator, c: u8) !void {
    // if cursor belwo all existing rows , append a new empty row
    if (E.cy == E.numrows) {
        try editorInsertRow(allocator, E.numrows, "");
    }
    // insert the character into current row at cursor column
    const row_index = @as(usize, @intCast(E.cy));
    try editorRowInsertChar(allocator, &E.row[row_index], E.cx, c);

    // advance cursor one column to right
    E.cx += 1;
}

/// Inserts a new row at position `at` with the given string content.
/// Shifts all rows at and after `at` down by one position.
fn editorInsertRow(allocator: std.mem.Allocator, at: c_int, s: []const u8) !void {
    // Guard: row index must be within valid bounds (0 to numrows, inclusive for append)
    if (at < 0 or at > E.numrows) {
        return;
    }

    const pos = @as(usize, @intCast(at));
    const numrows = @as(usize, @intCast(E.numrows));

    // Grow the row array to make room for one more row
    const new_rows = try allocator.realloc(E.row, numrows + 1);
    E.row = new_rows;

    // Shift all rows from pos onward down by one slot
    // This opens a hole at `pos` for the new row
    const src = E.row[pos..numrows];
    const dst = E.row[pos + 1 .. numrows + 1];
    std.mem.copyBackwards(erow, dst, src);

    // Allocate and copy the character content for the new row
    const chars = try allocator.alloc(u8, s.len + 1);
    @memcpy(chars[0..s.len], s);
    chars[s.len] = 0; // null terminator

    // Initialize the new row in the opened slot
    E.row[pos] = erow{
        .size = @as(c_int, @intCast(s.len)),
        .chars = chars,
        .rsize = 0,
        .render = &[_]u8{},
    };

    // Build the rendered version
    try editorUpdateRow(allocator, &E.row[pos]);

    // Update editor state
    E.numrows += 1;
    E.dirty += 1;
}

fn editorAppendRow(allocator: std.mem.Allocator, s: []const u8) !void {
    const at = @as(usize, @intCast(E.numrows));
    const new_row_count = at + 1;

    const new_rows = try allocator.realloc(E.row, new_row_count);
    E.row = new_rows;

    const chars_copy = try allocator.dupe(u8, s);

    E.row[at] = erow{
        .size = @as(c_int, @intCast(s.len)),
        .chars = chars_copy,
        .rsize = 0,
        .render = &[_]u8{}, //
    };

    try editorUpdateRow(allocator, &E.row[at]);

    E.numrows += 1;
    E.dirty += 1;
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

// concetenate all rows into a single string with newline between them
fn editorRowsToString(allocator: std.mem.Allocator, buflen: *usize) ![]u8 {
    // calculate total bytes needed
    var totlen: usize = 0;
    var j: c_int = 0;
    while (j < E.numrows) : (j += 1) {
        const row_index = @as(usize, @intCast(j));
        // each row attributes its size plus 1 byte for '\n'
        totlen += @as(usize, @intCast(E.row[row_index].size)) + 1;
    }
    // return totla length to caller
    buflen.* = totlen;
    // allocates full biuffer in one shot
    var buf = try allocator.alloc(u8, totlen);
    // istg i keep coming back to zig for some stupid reason and i hate memory mamanget i will switch to nim , i dont know whu i am keep comng back to this
    // secon press : copy each row and append new line
    var p: usize = 0; // current write positon in buf
    j = 0;

    while (j < E.numrows) : (j += 1) {
        const row_index = @as(usize, @intCast(j));
        const row = E.row[row_index];
        const row_size = @as(usize, @intCast(row.size));

        // copy the rows characters int othe buffer
        @memcpy(buf[p .. p + row_size], row.chars[0..row_size]);
        p += row_size;

        // append new line
        buf[p] = '\n';
        p += 1;
    }
    return buf;
}

fn editorSave(allocator: std.mem.Allocator) !void {
    if (E.filename == null) {
        E.filename = try editorPrompt(allocator,"Save as: %s (ESC t cancel)", null);
        if (E.filename==null){
            editorSetStatusMessage("save aborted", .{});
            return;
        }
    }

    const filename = E.filename orelse {
        editorSetStatusMessage("No filename", .{});
        return;
    };

    var len: usize = 0;
    const buf = try editorRowsToString(allocator, &len);
    defer allocator.free(buf);

    const fd = posix.open(filename, .{ .ACCMODE = .RDWR, .CREAT = true }, 0o644) catch |err| {
        editorSetStatusMessage("Can't save! I/O error: {s}", .{@errorName(err)});
        return;
    };
    defer posix.close(fd);

    posix.ftruncate(fd, @intCast(len)) catch |err| {
        editorSetStatusMessage("Can't save! I/O error: {s}", .{@errorName(err)});
        return;
    };

    const written = posix.write(fd, buf) catch |err| {
        editorSetStatusMessage("Can't save! I/O error: {s}", .{@errorName(err)});
        return;
    };

    if (written != len) {
        editorSetStatusMessage("Can't save! I/O error: incomplete write", .{});
        return;
    }
    E.dirty = 0;
    editorSetStatusMessage("{d} bytes written to disk", .{len});
}

// searches for query string in rendered text of all rows
// moves cursor to the first match. esc cancels the prompt
var find_last_match: c_int = -1;
var find_direction: c_int = 1;

fn editorFindCallback(query: []const u8, key: c_int) void {
    if (key == '\r' or key == '\x1b') {
        find_last_match = -1;
        find_direction = 1;
        return;
    } else if (key == @intFromEnum(editorKey.ARROW_RIGHT) or key == @intFromEnum(editorKey.ARROW_DOWN)) {
        find_direction = 1;
    } else if (key == @intFromEnum(editorKey.ARROW_LEFT) or key == @intFromEnum(editorKey.ARROW_UP)) {
        find_direction = -1;
    } else {
        find_last_match = -1;
        find_direction = 1;
    }

    if (find_last_match == -1) find_direction = 1;
    var current = find_last_match;

    var i: c_int = 0;
    while (i < E.numrows) : (i += 1) {
        current += find_direction;
        if (current == -1) {
            current = E.numrows - 1;
        } else if (current == E.numrows) {
            current = 0;
        }

        const row_index = @as(usize, @intCast(current));
        const row = &E.row[row_index];

        const match = std.mem.indexOf(u8, row.render[0..@as(usize, @intCast(row.rsize))], query);

        if (match) |match_index| {
            find_last_match = current;
            E.cy = current;
            E.cx = editorRowRxToCx(row, @as(c_int, @intCast(match_index)));
            E.rowoff = E.numrows;
            break;
        }
    }
}

fn editorFind(allocator: std.mem.Allocator) !void {
    const saved_cx = E.cx;
    const saved_cy = E.cy;
    const saved_coloff = E.coloff;
    const saved_rowoff = E.rowoff;

    const query = (editorPrompt(allocator, "Search: %s (Use ESC/Arrows/Enter)", editorFindCallback) catch return);
    if (query) |q| {
        allocator.free(q);
    } else {
        E.cx = saved_cx;
        E.cy = saved_cy;
        E.coloff = saved_coloff;
        E.rowoff = saved_rowoff;
    }
}

fn editorOpen(allocator: std.mem.Allocator, filename: []const u8) !void {
    // Free old filename if we had one
    if (E.filename) |old_name| {
        allocator.free(old_name);
    }
    // Duplicate new filename into owned memory
    E.filename = try allocator.dupe(u8, filename);

    var lines = try readit.readLines(allocator, filename);
    defer lines.deinit();

    for (lines.items) |raw_line| {
        var line = raw_line;

        while (line.len > 0 and (line[line.len - 1] == '\n' or line[line.len - 1] == '\r')) {
            line = line[0 .. line.len - 1];
        }

        try editorInsertRow(allocator, E.numrows, line);
    }

    E.dirty = 0;
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
    E.rx = 0;
    E.rowoff = 0;
    E.coloff = 0;
    E.numrows = 0;
    E.row = &[_]erow{};
    E.filename = &[_]u8{};
    E.statusmsg[0] = 0;
    E.statusmsg_time = 0;
    E.dirty = 0;

    // Pass pointers directly, just like C
    if (try getWindowSize(&E.screenrows, &E.screencols) == -1) {
        return error.WindowSizeFailed;
    }
    E.screenrows -= 2;
}

fn editorRowCxToRx(row: *erow, cx: c_int) c_int {
    var rx: c_int = 0; // rendered column position
    var j: c_int = 0;

    while (j < cx) : (j += 1) {
        if (row.chars[@intCast(j)] == '\t') {
            const tab_padding = (KILO_TAB_STOP - 1) - @rem(rx, KILO_TAB_STOP);

            rx += tab_padding;
        }
        rx += 1;
    }
    return rx;
}

// hmm
// converts a rendered screen column (rx) back to a character index(cx)
// inverse of editorRowCxToRx . handles tab expansion
fn editorRowRxToCx(row:*erow,rx:c_int) c_int {
    var cur_rx:c_int = 0; // current rendered column as we walk
    var cx: c_int  = 0; // character index we are calcuating

    // walk through each raw charactarter , accimumonating rendered columns
    while (cx<row.size) : (cx+=1){
        // if this char is a tab  add the padding to reach the next tab stop 
        if (row.chars[@intCast(cx)]=='\t'){
            cur_rx+=(KILO_TAB_STOP-1)-@rem(cur_rx,KILO_TAB_STOP);
        }
        // every character ( tab or normal ) advances at least 1 rendered column
        cur_rx+=1;
        // if we passed the target rx , the previous cx was the answer
        if (cur_rx>rx){
            return cx;
        }
    }
    // rx is past the end of the line: return the last valid cx
    return cx;
}

const editorKey = enum(c_int) { BACKSPACE = 127, ARROW_LEFT = 1000, ARROW_RIGHT, ARROW_UP, ARROW_DOWN, DEL_KEY, HOME_KEY, END_KEY, PAGE_UP, PAGE_DOWN };

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
var quit_times: i32 = KILO_QUIT_TIMES;
fn editorProcessKeypress() !void {

    // no static variable ?

    const c = try editorReadKey();

    switch (c) {
        '\r' => {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();
            try editorInsertNewline(allocator);
        },
        ctrlKey('x') => {
            if (E.dirty > 0 and quit_times > 0) {
                editorSetStatusMessage("WARNING!!! File has unsaved changes. Press ctrl-x {d} more times to quit. ", .{quit_times});
                quit_times -= 1;
                return;
            }

            _ = posix.write(posix.STDOUT_FILENO, "\x1b[2J") catch {};
            _ = posix.write(posix.STDOUT_FILENO, "\x1b[H") catch {};
            std.process.exit(0);
        },

        ctrlKey('s') => {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();
            try editorSave(allocator);
        },

        @intFromEnum(editorKey.HOME_KEY) => E.cx = 0,

        @intFromEnum(editorKey.END_KEY) => {
            if (E.cy < E.numrows) {
                E.cx = E.row[@intCast(E.cy)].size;
            }
        },

        ctrlKey('f')=>{
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();
            try editorFind(allocator);
        },

        @intFromEnum(editorKey.BACKSPACE), ctrlKey('h'), @intFromEnum(editorKey.DEL_KEY) => {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();
            if (c == @intFromEnum(editorKey.DEL_KEY)) {
                editorMoveCursor(@intFromEnum(editorKey.ARROW_RIGHT));
            }

            try editorDelChar(allocator);
        },

        @intFromEnum(editorKey.PAGE_UP), @intFromEnum(editorKey.PAGE_DOWN) => {
            if (c == @intFromEnum(editorKey.PAGE_UP)) {
                E.cy = E.rowoff;
            } else {
                E.cy = E.rowoff + E.screenrows - 1;
                if (E.cy > E.numrows) {
                    E.cy = E.numrows;
                }
            }

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

        '\x1b', ctrlKey('l') => {},

        else => {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();
            try editorInsertChar(allocator, @intCast(c));
        },
    }
    quit_times = KILO_QUIT_TIMES;
}

fn editorDrawMessageBar(allocator: std.mem.Allocator, ab: *abuf) !void {
    try abAppend(allocator, ab, "\x1b[K");
    // Calculate how long the status message actually is
    var msglen: usize = 0;
    while (msglen < E.statusmsg.len and E.statusmsg[msglen] != 0) {
        msglen += 1;
    }
    // no overflow
    if (msglen > @as(usize, @intCast(E.screencols))) {
        msglen = @as(usize, @intCast(E.screencols));
    }

    const now = std.time.timestamp();
    const is_recent = (now - E.statusmsg_time) < 5;

    if (msglen > 0 and is_recent) {
        try abAppend(allocator, ab, E.statusmsg[0..msglen]);
    }
}

fn editorDrawStatusBar(allocator: std.mem.Allocator, ab: *abuf) !void {
    // Enable reverse video (inverted colors) for the status bar
    try abAppend(allocator, ab, "\x1b[7m");

    // --- Left side: filename, line count, and dirty marker ---
    var status: [80]u8 = undefined;

    const filename_display = E.filename orelse "[No Name]";
    const dirty_marker = if (E.dirty > 0) " (modified)" else "";

    // {s:.20} truncates filename to 20 chars max
    const formatted = try std.fmt.bufPrint(&status, "{s:.20} - {d} lines{s}", .{
        filename_display,
        E.numrows,
        dirty_marker,
    });

    var len = @as(c_int, @intCast(formatted.len));
    if (len > E.screencols) {
        len = E.screencols;
    }

    try abAppend(allocator, ab, formatted[0..@intCast(len)]);

    // --- Right side: current line / total lines ---
    var rstatus: [80]u8 = undefined;

    // E.cy is 0-based internally, so add 1 for human-readable display
    const rformatted = try std.fmt.bufPrint(&rstatus, "{d}/{d}", .{
        E.cy + 1,
        E.numrows,
    });
    const rlen = @as(c_int, @intCast(rformatted.len));

    // Fill middle with spaces, but when we hit exactly the right-side width,
    // inject the cursor position info instead of a space
    while (len < E.screencols) : (len += 1) {
        if (E.screencols - len == rlen) {
            // Perfect fit: append right-side info and we're done
            try abAppend(allocator, ab, rformatted);
            break;
        } else {
            // Not there yet: keep padding with spaces
            try abAppend(allocator, ab, " ");
        }
    }

    // Reset all text attributes back to normal
    try abAppend(allocator, ab, "\x1b[m");

    // Move cursor to next line so message bar can draw on its own row
    try abAppend(allocator, ab, "\r\n");
}

fn editorRefreshScreen(allocator: std.mem.Allocator) !void {
    try editorScroll();

    var ab = abuf.INIT;
    // Defers cleanup so it always runs, preventing memory leaks on error
    defer abFree(allocator, &ab);

    // Fixed: changed capital 'L' to lowercase 'l'
    try abAppend(allocator, &ab, "\x1b[?25l");
    try abAppend(allocator, &ab, "\x1b[H");

    // draw the tildes/text rows
    try editorDrawRows(allocator, &ab);
    // status bar
    try editorDrawStatusBar(allocator, &ab);
    // messsage bar
    try editorDrawMessageBar(allocator, &ab);

    // omfg chapter 4 done
    // 3 more chapters , please be easy

    var buf: [32]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ (E.cy - E.rowoff) + 1, (E.rx - E.coloff) + 1 });
    try abAppend(allocator, &ab, msg);

    try abAppend(allocator, &ab, "\x1b[?25h");

    // output complete buffer to terminal
    _ = posix.write(posix.STDOUT_FILENO, ab.b) catch {};
}

fn editorSetStatusMessage(comptime fmt: []const u8, args: anytype) void {
    // format messag directly into fixed size buffer
    _ = std.fmt.bufPrint(&E.statusmsg, fmt, args) catch {
        @memset(&E.statusmsg, 0);
        return;
    };

    // record current timestamp
    E.statusmsg_time = std.time.timestamp();
}

// ask the user for input at bottom of screen
const PromptCallback = *const fn ([]const u8, c_int) void;

fn editorPrompt(allocator: std.mem.Allocator, prompt: []const u8, callback: ?PromptCallback) !?[]u8 {
    // Start with a 128-byte buffer, grow dynamically as needed
    var bufsize: usize = 128;
    var buf = try allocator.alloc(u8, bufsize);

    // Track actual string length (not buffer capacity)
    var buflen: usize = 0;
    buf[0] = 0; // null terminator so bufPrint treats it as empty string

    while (true) {
        // Show prompt + current input in status bar
        editorSetStatusMessage("{s}{s}", .{ prompt, buf[0..buflen] });
        try editorRefreshScreen(allocator);

        const c = try editorReadKey();

        if (c==@intFromEnum(editorKey.DEL_KEY) or c==ctrlKey('h') or c==@intFromEnum(editorKey.BACKSPACE)){
            if (buflen!=0){
                buflen-=1;
            }
        }
        else if (c=='\x1b'){
            editorSetStatusMessage("", .{});
            if (callback) |cb| cb(buf[0..buflen], c);
            allocator.free(buf);
            return null;
        }
        else if (c == '\r') {
            // Enter pressed: return buffer if non-empty
            if (buflen != 0) {
                editorSetStatusMessage("", .{});
                if (callback) |cb| cb(buf[0..buflen], c);
                const exact = try allocator.realloc(buf, buflen + 1);
                return exact;
            }
            // Empty input on Enter: keep prompting (don't return)
        } else if (!std.ascii.isControl(@intCast(c)) and c < 128) {
            // Printable ASCII character: append to buffer
            if (buflen == bufsize - 1) {
                // Buffer full: double the capacity
                bufsize *= 2;
                buf = try allocator.realloc(buf, bufsize);
            }
            buf[buflen] = @intCast(c);
            buflen += 1;
            buf[buflen] = 0; // maintain null terminator
        }
        if (callback) |cb| cb(buf[0..buflen], c);
    }
}

fn editorMoveCursor(key: c_int) void {
    const row: ?*erow = if (E.cy < E.numrows) &E.row[@intCast(E.cy)] else null;

    switch (key) {
        @intFromEnum(editorKey.ARROW_LEFT) => {
            if (E.cx != 0) {
                E.cx -= 1;
            } else if (E.cy > 0) {
                // 1. Move up to the previous line
                E.cy = E.cy - 1;

                const target_row_index = @as(usize, @intCast(E.cy));
                const previous_row = E.row[target_row_index];

                E.cx = @as(c_int, @intCast(previous_row.chars.len));
            }
        },
        @intFromEnum(editorKey.ARROW_RIGHT) => {
            if (row) |r| {
                if (E.cx < r.chars.len) {
                    E.cx += 1;
                }
            } else if (row) |r| {
                const row_len = @as(c_int, @intCast(r.chars.len));

                if (E.cx == row_len) {
                    E.cy += 1;
                    E.cx = 0;
                }
            }
        },
        @intFromEnum(editorKey.ARROW_UP) => {
            if (E.cy != 0) E.cy -= 1;
        },
        @intFromEnum(editorKey.ARROW_DOWN) => {
            if (E.cy < E.numrows) E.cy += 1;
        },
        else => {},
    }
    const rowlen = if (row) |r| r.chars.len else 0;

    if (E.cx > @as(c_int, @intCast(rowlen))) {
        E.cx = @as(c_int, @intCast(rowlen));
    }
}

fn editorScroll() !void {
    E.rx = 0;
    if (E.cy < E.numrows) {
        E.rx = editorRowCxToRx(&E.row[@intCast(E.cy)], E.cx);
    }
    if (E.cy < E.rowoff) {
        E.rowoff = E.cy;
    }
    if (E.cy >= E.rowoff + E.screenrows) {
        E.rowoff = E.cy - E.screenrows + 1;
    }
    if (E.rx < E.coloff) {
        E.coloff = E.rx;
    }
    if (E.rx >= E.coloff + E.screencols) {
        E.coloff = E.rx - E.screencols + 1;
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
            const current_row = E.row[@as(usize, @intCast(filerow))];

            const u_coloff = @as(usize, @intCast(E.coloff));

            var len: usize = 0;

            const u_rsize = @as(usize, @intCast(current_row.size));

            if (u_rsize > u_coloff) {
                len = u_rsize - u_coloff;
            }

            if (len > @as(usize, @intCast(E.screencols))) {
                len = @as(usize, @intCast(E.screencols));
            }

            if (len > 0) {
                const end = u_coloff + len;
                try abAppend(allocator, ab, current_row.render[u_coloff..end]);
            }
        }

        // Clear the remainder of the current line from the cursor to the right margin
        try abAppend(allocator, ab, "\x1b[K");

        // Append a newline carriage return for every row except the absolute last line
        // if (y < E.screenrows - 1) {
        try abAppend(allocator, ab, "\r\n");
        // }
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

    // Enter raw mode first so we control the terminal completely
    _ = try enableRawMode();
    // Ensure raw mode is disabled even if we crash or return early
    defer disableRawMode();

    // Initialize editor state (screen size, cursor position, etc.)
    try initEditor();

    // If a filename was provided on command line, open it
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len >= 2) {
        try editorOpen(allocator, args[1]);
    }

    // Show initial help message in the status bar
    editorSetStatusMessage("HELP: Ctrl-X = quit | Ctrl-S = save | Ctrl-F = find", .{});

    // Main event loop: draw screen, wait for input, repeat forever
    while (true) {
        try editorRefreshScreen(allocator);
        try editorProcessKeypress();
    }
}
