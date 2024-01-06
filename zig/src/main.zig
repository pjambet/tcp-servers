const std = @import("std");
const net = std.net;
const fs = std.fs;
const os = std.os;
const ArrayList = std.ArrayList;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();

    var server = net.StreamServer.init(.{
        .reuse_address = true,
        .reuse_port = true,
    });
    defer server.deinit();

    try server.listen(net.Address.parseIp("127.0.0.1", 3000) catch unreachable);
    std.debug.print("listening at {}\n", .{server.listen_address});
    std.debug.print("Server.sockfd {?}\n", .{server.sockfd});

    const server_fd = server.sockfd.?;

    var pollfds = ArrayList(os.pollfd).init(allocator);
    defer pollfds.deinit();

    var clients = std.AutoArrayHashMap(i32, net.StreamServer.Connection).init(allocator);
    defer clients.deinit();

    while (true) {
        pollfds.clearRetainingCapacity();
        // Add the server first
        try pollfds.append(.{ .fd = server_fd, .events = os.POLL.IN, .revents = 0 });
        // Then all connected clients
        for (clients.values()) |client| {
            try pollfds.append(.{ .fd = client.stream.handle, .events = os.POLL.IN, .revents = 0 });
        }

        var poll_result = try os.poll(pollfds.items, 15000);
        std.debug.print("Poll result {?}\n", .{poll_result});
        for (pollfds.items) |pollfd| {
            std.debug.print("items after poll {?}\n", .{pollfd});
        }
        // std.debug.print("items after poll {?}\n", .{pollfds.values[0]});
        for (pollfds.items) |pollfd| {
            if (pollfd.revents & os.POLL.HUP != 0) {
                std.debug.print("HUP, removing and continuing\n", .{});
                _ = clients.orderedRemove(pollfd.fd);
                break;
            } else if (pollfd.revents & os.POLL.IN == 1) {
                if (pollfd.fd == server_fd) {
                    std.debug.print("Done polling\n", .{});
                    var conn = try server.accept();
                    // defer conn.stream.close();
                    std.debug.print("conn handle {?}\n", .{conn.stream.handle});
                    try clients.put(conn.stream.handle, conn);
                    _ = try conn.stream.write("server: welcome to the chat server\n");
                } else {
                    var conn = clients.get(pollfd.fd).?;
                    var buf: [100]u8 = undefined;
                    const amt = try conn.stream.read(&buf);
                    const msg = buf[0..amt];
                    std.debug.print("received: {?}\n", .{amt});
                    std.debug.print("received: {s}\n", .{msg});
                    _ = try conn.stream.write("server: You said something, thanks\n");
                }
            }
        }
    }

    std.os.exit(0);
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
