const std = @import("std");
const net = std.net;
const fs = std.fs;
const os = std.os;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();

    var server = net.StreamServer.init(.{});
    defer server.deinit();

    // TODO handle concurrent accesses to this hash map
    var room = Room{ .clients = std.AutoHashMap(*Client, void).init(allocator) };

    try server.listen(net.Address.parseIp("127.0.0.1", 0) catch unreachable);
    std.debug.print("listening at {}\n", .{server.listen_address});
    std.debug.print("Server.sockfd {?}\n", .{server.sockfd});

    // var fd_set = os.fd_set{};
    // std.debug.print("fd_set {}\n", .{fd_set});

    const fd = server.sockfd.?;

    var fds2: [1]os.pollfd = .{.{ .fd = fd, .events = os.POLL.IN, .revents = 0 }};

    while (true) {
        const client = try allocator.create(Client);
        std.debug.print("Polling\n", .{});
        _ = try os.poll(&fds2, 15000);
        std.debug.print("Done polling\n", .{});

        client.* = Client{
            .conn = try server.accept(),
            .handle_frame = async client.handle(&room),
        };
        try room.clients.putNoClobber(client, {});
    }
}
const Client = struct {
    conn: net.StreamServer.Connection,
    handle_frame: @Frame(handle),

    fn handle(self: *Client, room: *Room) !void {
        _ = try self.conn.stream.write("server: welcome to teh chat server\n");
        while (true) {
            var buf: [100]u8 = undefined;
            const amt = try self.conn.stream.read(&buf);
            const msg = buf[0..amt];
            room.broadcast(msg, self);
        }
    }
};
const Room = struct {
    clients: std.AutoHashMap(*Client, void),

    fn broadcast(room: *Room, msg: []const u8, sender: *Client) void {
        var it = room.clients.keyIterator();
        while (it.next()) |key_ptr| {
            const client = key_ptr.*;
            if (client == sender) continue;
            _ = client.conn.stream.write(msg) catch |e| std.debug.print("unable to send: {}\n", .{e});
        }
    }
};

// const std = @import("std");
// const os = std.os;

// pub fn main() !void {
//     // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
//     std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

//     // stdout is for the actual output of your application, for example if you
//     // are implementing gzip, then only the compressed bytes should be sent to
//     // stdout, not any debugging messages.
//     const stdout_file = std.io.getStdOut().writer();
//     var bw = std.io.bufferedWriter(stdout_file);
//     const stdout = bw.writer();

//     try stdout.print("Run `zig build test` to run the tests.\n", .{});

//     try bw.flush(); // don't forget to flush!
// }

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
