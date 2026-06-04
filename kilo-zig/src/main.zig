const std = @import("std");
const posix = std.posix;


fn die(msg: []const u8, err:anyerror) noreturn {
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

    return orig_termios;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn();

    const orig_termios = try enableRawMode();
    defer _ = posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, orig_termios) catch |err| {
        die("tcsetattr",err);
    };

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

        if (c == 'q') break;
    }
}
