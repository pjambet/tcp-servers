const std = @import("std");
const os = std.os;

pub fn main() !void {
    var fds2: [1]os.pollfd = .{.{ .fd = os.STDOUT_FILENO, .events = os.POLL.OUT, .revents = 0 }};
    _ = try os.poll(&fds2, 1);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello, {s}!\n", .{"world"});
}
