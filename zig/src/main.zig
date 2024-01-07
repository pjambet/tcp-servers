const std = @import("std");
const expect = std.testing.expect;
const net = std.net;
const fs = std.fs;
const os = std.os;
const ArrayList = std.ArrayList;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();
    defer {
        const deinit_status = general_purpose_allocator.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }

    var server = net.StreamServer.init(.{
        .reuse_address = true,
        .reuse_port = true,
    });
    defer server.deinit();

    try server.listen(net.Address.parseIp("127.0.0.1", 3000) catch unreachable);
    std.debug.print("Yo!\n", .{});
    std.debug.print("listening at {}\n", .{server.listen_address});
    std.debug.print("Server.sockfd {?}\n", .{server.sockfd});

    const server_fd = server.sockfd.?;

    var pollfds = ArrayList(os.pollfd).init(allocator);
    defer pollfds.deinit();

    var clients = std.AutoArrayHashMap(i32, net.StreamServer.Connection).init(allocator);
    defer clients.deinit();

    // var db = std.StringHashMap([]const u8).init(allocator);
    var db = std.BufMap.init(allocator);
    // var db = std.StringArrayHashMap([]const u8).init(allocator);
    defer db.deinit();
    // try db.put("foo", "bar");
    // try db.put("foo", undefined);

    outer: while (true) {
        pollfds.clearRetainingCapacity();
        // Add the server first
        try pollfds.append(.{ .fd = server_fd, .events = os.POLL.IN, .revents = 0 });
        // Then all connected clients
        for (clients.values()) |client| {
            try pollfds.append(.{ .fd = client.stream.handle, .events = os.POLL.IN, .revents = 0 });
        }

        var poll_result = try os.poll(pollfds.items, 35000);
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
                    // _ = try conn.stream.write("server: welcome to the chat server\n");
                } else {
                    var conn = clients.get(pollfd.fd).?;
                    var buf: [100]u8 = undefined;
                    const amt = try conn.stream.read(&buf);
                    const msg = buf[0..amt];
                    std.debug.print("received: '{?}'\n", .{amt});
                    std.debug.print("received: '{s}'\n", .{msg});
                    std.debug.print("received: '{d}'\n", .{msg});
                    var partsIterator = std.mem.splitScalar(u8, msg, ' ');
                    var parts = ArrayList([]const u8).init(allocator);
                    defer parts.deinit();
                    while (partsIterator.next()) |part| {
                        try parts.append(std.mem.trim(u8, part, "\n\r"));
                    }

                    if (msg.len >= 4 and std.mem.eql(u8, msg[0..4], "QUIT")) {
                        conn.stream.close();
                        _ = clients.orderedRemove(pollfd.fd);
                        break;
                    } else if (msg.len >= 4 and std.mem.eql(u8, msg[0..4], "STOP")) {
                        break :outer;
                    }

                    if (parts.items.len < 2) {
                        _ = try conn.stream.write("early, too short\n");
                        break;
                    }
                    var command = parts.items[0];
                    var key = parts.items[1];
                    // std.debug.print("command: '{s}'\n", .{command});
                    // std.debug.print("key: '{s}'\n", .{key});

                    if (std.mem.eql(u8, command, "GET")) {
                        std.debug.print("message is GET\n", .{});
                        // var list = ArrayList(u8).init(allocator);
                        // defer list.deinit(); // INTENTIONAL LEAK
                        var db_iter = db.iterator();
                        while (db_iter.next()) |pair| {
                            std.debug.print("key: {}, value: '{}'\n", .{ pair.key_ptr, pair.value_ptr });
                            std.debug.print("key: {s}, value: '{s}'\n", .{ pair.key_ptr.*, pair.value_ptr.* });
                            std.debug.print("key: {d}, value: '{d}'\n", .{ pair.key_ptr.*, pair.value_ptr.* });
                        }
                        var response = db.get(key); // orelse "";
                        if (response) |val| {
                            std.debug.print("response: {s}\n", .{val});

                            var response_string = try std.fmt.allocPrint(allocator, "{s}\n", .{val});
                            defer allocator.free(response_string);

                            // _ = try std.fmt.format(list.writer(), "{s}\n", .{val});
                            // _ = try std.fmt.format(list.writer(), "\n", .{});
                            _ = try conn.stream.write(response_string);
                        } else {
                            _ = try conn.stream.write("\n");
                        }
                    } else if (std.mem.eql(u8, command, "SET")) {
                        if (parts.items.len < 3) {
                            _ = try conn.stream.write("SET, too short\n");
                            break;
                        }
                        var value = parts.items[2];
                        std.debug.print("value: '{s}'\n", .{value});
                        std.debug.print("value: '{d}'\n", .{value});

                        // var list = ArrayList(u8).init(allocator);
                        // defer list.deinit();

                        // var key2 = try allocator.dupe(u8, key);
                        // defer allocator.free(key2);
                        // var value2 = try allocator.dupe(u8, value);
                        // defer allocator.free(value2);
                        // std.debug.print("key2: '{s}'\n", .{key2});
                        // std.debug.print("key2: '{d}'\n", .{key2});
                        // std.debug.print("typeInfo(key2): '{}'\n", .{@typeInfo(@TypeOf(key2))});
                        _ = try db.put(key, value);

                        var keys_iter = db.iterator();
                        std.debug.print("keys: ", .{});
                        while (keys_iter.next()) |pair| {
                            std.debug.print("{s}, ", .{pair.key_ptr.*});
                        }
                        std.debug.print("\n", .{});
                        var iter = db.iterator();
                        while (iter.next()) |pair| {
                            std.debug.print("key: {s}, value: '{s}'\n", .{ pair.key_ptr, pair.value_ptr });
                            std.debug.print("key: {s}, value: '{s}'\n", .{ pair.key_ptr.*, pair.value_ptr.* });
                        }

                        // _ = try std.fmt.format(list.writer(), "{s}\n", .{value});
                        _ = try conn.stream.write("OK\n");
                    } else if (std.mem.eql(u8, command, "DEL")) {
                        // var removed = db.remove(key);
                        // var removed = db.swapRemove(key);
                        var entryOpt = db.get(key);
                        if (entryOpt) |entry| {
                            std.debug.print("key: {s}'\n", .{entry});

                            // Seems like don't need to free for an array hash map?

                            // try expect(@TypeOf(entry.key_ptr.*) == []const u8);
                            // try expect(@TypeOf(entry.key_ptr) == *[]const u8);
                            // allocator.free(entry.key_ptr.*);
                            // allocator.free(entry.value_ptr.*);
                            // allocator.destroy(entry.key_ptr);
                            // _ = db.swapRemove(key);
                            // _ = db.orderedRemove(key);
                            _ = db.remove(key);

                            _ = try conn.stream.write("1\n");
                        } else {
                            _ = try conn.stream.write("0\n");
                        }
                    } else if (std.mem.eql(u8, command, "INCR")) {
                        std.debug.print("message is INCR\n", .{});
                        var existing_string_opt = db.get(key);
                        if (existing_string_opt) |existing_string| {
                            if (std.fmt.parseInt(i32, existing_string, 10)) |number| {
                                var new_value = number + 1;
                                var list = ArrayList(u8).init(allocator);
                                defer list.deinit();

                                _ = try std.fmt.format(list.writer(), "{?}", .{new_value});
                                // std.debug.print("putting {s}\n", .{list.items});
                                var new_str = try allocator.dupe(u8, list.items);
                                defer allocator.free(new_str);
                                _ = try db.put(key, new_str);

                                var list2 = ArrayList(u8).init(allocator);
                                defer list2.deinit();
                                _ = try std.fmt.format(list2.writer(), "{?}\n", .{new_value});
                                _ = try conn.stream.write(list2.items);
                            } else |_| {
                                _ = try conn.stream.write("ERR value is not an integer or out of range\n");
                            }
                        } else {
                            _ = try db.put(key, "1");
                            _ = try conn.stream.write("1\n");
                        }
                    } else if (std.mem.eql(u8, command, "STOP")) {
                        break :outer;
                    } else {
                        std.debug.print("unknown command\n", .{});
                        _ = try conn.stream.write("server: Unknown command\n");
                    }
                }
            }
        }
    }

    // Memory leak playground
    const bytes = try allocator.alloc(u8, 100);
    defer allocator.free(bytes);
    const u32_ptr = try allocator.create(u32);
    defer allocator.destroy(u32_ptr);
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
