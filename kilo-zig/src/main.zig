const std = @import("std");
const posix = std.posix;
const stdout = std.io.getStdOut().writer();


fn enableRawMode() !posix.termios {
    // tcgetattr(STDIN_FILENO, &orig_termios);
    const orig_termios = try posix.tcgetattr(posix.STDIN_FILENO);

    // atexit(disableRawMode);
    // zig doesnt have atexit so we use defer , we move it to main function not here because we want to disable raw mode when main function exits not when this function exits
    // struct termios raw = orig_termios;
    // tcgetattr(STDIN_FILENO, &raw);
    var raw = orig_termios;

    // raw.c_lflag &= ~(ECHO);
    // c uses bitwise , zig wont 
    // clea the echo and icanon flags via struct properties
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    // turn of ctrl c and ctrl z signals
    raw.lflag.ISIG = false;
    // disable ctrl s and ctrl q
    raw.iflag.IXON = false; // lives in iflag not lflag
    // disable ctrl v and ctrl o
    raw.lflag.IEXTEN = false;
    // iflag is for input  ,o for output and lflag for local
    // disable ctrl M
    raw.iflag.ICRNL = false;
    // turn off all output processing
    raw.oflag.OPOST = false;
    // misc flags
    raw.iflag.BRKINT = false; // disable ctrl d
    raw.iflag.INPCK = false; // disable parity checking
    raw.iflag.ISTRIP = false; // disable stripping of 8th bit
    raw.iflag.IXON = false; // disable ctrl s and ctrl q
    raw.cflag.CS8 = true; // set character size to 8 bits per byte

    // while waiting indefinely we can add a timeout or aimated cursor
    raw.c_cc[posix.VMIN] = 0; // minimum number of bytes of input needed before read() can return
    raw.c_cc[posix.VTIME] = 1; // maximum amount of time to wait before read() can return

    // tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
    // apply changes using flush action
    try posix.tcsetattr(posix.STDIN_FILENO,.FLUSH,raw);

    return orig_termios;
}

pub fn main() !void {
    const orig_termios = try enableRawMode();

    // cleanup
    defer posix.tcsetattr(posix.STDIN_FILENO,.FLUSH,orig_termios) catch {};
    
    // char c;
    var c:u8 = undefined; 
    // while (read(STDIN_FILENO,&c,1)==1 && c!='q')
    while (posix.read(posix.STDIN_FILENO,std.mem.asBytes(&c))) |bytes_read| {
        if (bytes_read==0 or c=='q') break;
        // while not stoppping
        if (std.ascii.isControl(c)){
            try stdout.print("{d}\r\n",.{c});
        }else {
            try stdout.print("{c} ('{c}')\r\n",.{c,c});
        }

    }else |_| {
        try stdout.print("error\r\n",.{});
    }
    return;
}
