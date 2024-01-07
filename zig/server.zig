const std = @import("std");
const expect = std.testing.expect;
const os = std.os;

const CustomEntry = struct {
    string: []const u8 = undefined,
    key_p: []u8 = undefined,
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();

    defer {
        const deinit_status = general_purpose_allocator.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }

    // var fd: [1]os.pollfd = .{.{ .fd = os.STDOUT_FILENO, .events = os.POLL.OUT, .revents = 0 }};
    // _ = try os.poll(&fds2, 1);

    // const stdout = std.io.getStdOut().writer();
    // try stdout.print("Hello, {s}!\n", .{"world"});

    // var hashMap = std.StringHashMap([]const u8).init(allocator);
    // var hashMap = std.StringHashMap(*CustomEntry).init(allocator);
    var hashMap = std.BufMap.init(allocator);
    defer hashMap.deinit();
    {
        // try hashMap.put("foo", &"bar");
        // var key: []const u8 = "foo";
        // var bar: []const u8 = "bar";
        // var keySlice = try allocator.dupe(u8, key);
        // var barSlice = try allocator.dupe(u8, bar);
        // defer allocator.free(keySlice);
        // defer allocator.free(barSlice);
        // allocator.free(barSlice);
        // std.debug.print("keySlice: {}\n", .{&keySlice});
        // std.debug.print("barSlice: {}\n", .{&barSlice});
        // try hashMap.put(keySlice, barSlice);
        var key = try std.fmt.allocPrint(allocator, "{s}", .{"foo"});
        defer allocator.free(key);
        var value = try std.fmt.allocPrint(allocator, "{s}", .{"123"});
        defer allocator.free(value);

        std.debug.print("key: {s}\n", .{key});
        std.debug.print("key: {d}\n", .{key});
        std.debug.print("key: {}\n", .{&key});

        std.debug.print("value: {s}\n", .{value});
        std.debug.print("value: {}\n", .{&value});
        // var node = try allocator.create(Node);
        // errdefer allocator.destroy(node);
        // node.* = .{ .next = self.head, .item = item, .prev = null };
        // var entry_v = try allocator.create(CustomEntry);
        // defer allocator.destroy(entry_v);
        // entry_v.* = CustomEntry{
        //     .string = value,
        //     .key_p = key,
        // };

        try hashMap.put(key, value);
        // _ = hashMap.remove("foo");
        // // std.debug.print("foo: {s}\n", .{hashMap.get("foo").?});
        // std.debug.print("foo: {s}\n", .{hashMap.get("foo").?});
        // var entryOpt = hashMap.getEntry("foo");
        // if (entryOpt) |entry| {
        //     std.debug.print("entry: {}\n", .{entry});
        //     std.debug.print("entry.key_ptr: {}\n", .{entry.key_ptr});
        //     std.debug.print("entry.value_ptr: {}\n", .{entry.value_ptr});
        //     std.debug.print("entry.key_ptr.*: {s}\n", .{entry.key_ptr.*});
        //     // std.debug.print("entry.value_ptr.*.key_p: {s}\n", .{entry.value_ptr.*.key_p});
        //     // std.debug.print("entry.value_ptr.*.key_p: {d}\n", .{entry.value_ptr.*.key_p});
        //     // std.debug.print("entry.value_ptr.*.*: {s}\n", .{entry.value_ptr.*.*});
        //     // std.debug.print("&entry.value_ptr.*: {s}\n", .{&entry.value_ptr.*});

        //     // allocator.free(entry.key_ptr.*);
        //     // allocator.free(entry.value_ptr.*);
        //     _ = hashMap.remove("foo");
        //     //     // allocator.free(entry.key_ptr.*);
        //     defer allocator.free(entry.value_ptr.*);
        // }

        // var entryOpt2 = hashMap.getEntry("foo");
        var contains = hashMap.get("foo");
        if (contains) |_| {
            _ = hashMap.remove("foo");
            std.debug.print("Found entry\n", .{});
        } else {
            std.debug.print("No entry\n", .{});
        }

        // if (hashMap.get("foo")) |value| {
        //     std.debug.print("foo: {s}\n", .{value});
        // } else {
        //     std.debug.print("foo: NO_VALUE\n", .{});
        // }
    }
    const bytes = try allocator.alloc(u8, 100);
    defer allocator.free(bytes);
    // allocator.free(barSlice);
    // std.debug.print("foo: {s}\n", .{barSlice});

    // hashMap.clearAndFree();
}
