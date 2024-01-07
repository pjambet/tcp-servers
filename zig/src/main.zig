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

    var db = std.StringHashMap(i32).init(allocator);
    defer db.deinit();
    // try db.put("foo", "bar");
    try db.put("foo", 123);

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
                    var partsIterator = std.mem.splitScalar(u8, msg, ' ');
                    var parts = ArrayList([]const u8).init(allocator);
                    defer parts.deinit();
                    while (partsIterator.next()) |part| {
                        try parts.append(std.mem.trim(u8, part, "\n"));
                    }
                    if (parts.items.len < 2) {
                        _ = try conn.stream.write("too short\n");
                        break;
                    }
                    var command = parts.items[0];
                    var key = parts.items[1];
                    std.debug.print("command: '{s}'\n", .{command});
                    std.debug.print("key: '{s}'\n", .{key});

                    if (std.mem.eql(u8, command, "GET")) {
                        std.debug.print("message is GET\n", .{});
                        var list = ArrayList(u8).init(allocator);
                        defer list.deinit();
                        var iter = db.iterator();
                        while (iter.next()) |pair| {
                            std.debug.print("key: {s}, value: '{?}'\n", .{ pair.key_ptr.*, pair.value_ptr.* });
                        }
                        var response = db.get(key); // orelse "";
                        if (response) |val| {
                            std.debug.print("response: {?}\n", .{val});
                            _ = try std.fmt.format(list.writer(), "{?}\n", .{val});
                            _ = try conn.stream.write(list.items);
                        } else {
                            _ = try conn.stream.write("\n");
                        }
                    } else if (std.mem.eql(u8, command, "SET")) {
                        if (parts.items.len < 3) {
                            _ = try conn.stream.write("too short\n");
                            break;
                        }
                        var value = parts.items[2];
                        std.debug.print("value: '{s}'\n", .{value});
                        std.debug.print("value: '{d}'\n", .{value});

                        var list = ArrayList(u8).init(allocator);
                        defer list.deinit();

                        // var k2 = try allocator.create([]const u8);
                        // k2.foo();

                        _ = try db.put(key, 456);
                        var iter = db.iterator();
                        while (iter.next()) |pair| {
                            std.debug.print("key: {s}, value: '{s}'\n", .{ pair.key_ptr, pair.value_ptr });
                            std.debug.print("key: {s}, value: '{?}'\n", .{ pair.key_ptr.*, pair.value_ptr.* });
                        }

                        _ = try std.fmt.format(list.writer(), "{?}\n", .{value});
                        _ = try conn.stream.write(list.items);
                    } else if (std.mem.eql(u8, command, "DEL")) {
                        var removed = db.remove(key);
                        if (removed) {
                            _ = try conn.stream.write("1\n");
                        } else {
                            _ = try conn.stream.write("0\n");
                        }
                    } else if (std.mem.eql(u8, command, "INCR")) {
                        std.debug.print("message is INCR\n", .{});
                        _ = try conn.stream.write("server: You said something, thanks\n");
                    } else {
                        std.debug.print("unknown command\n", .{});
                        _ = try conn.stream.write("server: Unknown command\n");
                    }
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
