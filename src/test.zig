const std = @import("std");
const testing = std.testing;
const graph = @import("blitzdep.zig");

test "basic chain" {
    var g = graph.Graph(u32, 10, 20){};
    _ = try g.add(0, 1);
    _ = try g.add(1, 2);
    _ = try g.add(3, 1);
    _ = try g.add(4, 5);

    const sorted = try g.resolve();
    var pos = [_]usize{0} ** 6;
    for (sorted, 0..) |id, i| {
        if (id < 6) pos[id] = i;
    }

    try testing.expect(pos[0] < pos[1]);
    try testing.expect(pos[1] < pos[2]);
    try testing.expect(pos[3] < pos[1]);
}

test "comptime large" {
    comptime {
        @setEvalBranchQuota(50000);
        var g = graph.Graph(u32, 2000, 4000){};
        var i: u32 = 0;
        while (i < 1999) : (i += 1) {
            _ = try g.add(i, i + 1);
        }
        const sorted = try g.resolve();
        try testing.expectEqual(@as(usize, 2000), sorted.len);
        i = 0;
        while (i < sorted.len) : (i += 1) {
            try testing.expectEqual(i, sorted[i]);
        }
    }
}

test "init clean" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const G = graph.Graph(u32, 100, 200);
    for (0..20) |_| {
        const g = try alloc.create(G);
        @memset(std.mem.asBytes(g), 0xAA);
        g.* = .{};
        try testing.expectEqual(@as(u32, 0), g.n);
        try testing.expectEqual(@as(u32, 0), g.high);
        for (g.head) |h| try testing.expect(h == null);
    }
}

test "structure" {
    var g = graph.Graph(u32, 50, 50){};
    _ = try g.add(0, 1);
    _ = try g.add(0, 2);
    _ = try g.add(1, 3);

    try testing.expectEqual(@as(u32, 3), g.high);

    var seen1 = false;
    var seen2 = false;
    var count: usize = 0;
    var it = g.head[0];
    while (it) |e| : (it = g.next[e]) {
        count += 1;
        if (g.dest[e] == 1) seen1 = true;
        if (g.dest[e] == 2) seen2 = true;
    }
    try testing.expect(seen1 and seen2 and count == 2);

    var seen3 = false;
    it = g.head[1];
    while (it) |e| : (it = g.next[e]) {
        if (g.dest[e] == 3) seen3 = true;
    }
    try testing.expect(seen3);
}

test "indegree" {
    var g = graph.Graph(u32, 10, 10){};
    _ = try g.add(0, 2);
    _ = try g.add(1, 2);
    _ = try g.resolve();

    var deg: u32 = 0;
    for (0..g.n) |i| {
        var it = g.head[i];
        while (it) |e| {
            if (g.dest[e] == 2) deg += 1;
            it = g.next[e];
        }
    }
    try testing.expectEqual(@as(u32, 2), deg);
}

test "fuzz acyclic" {
    var prng = std.Random.DefaultPrng.init(0x12345678);
    const rng = prng.random();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const G = graph.Graph(u32, 256, 2000);
    var edges: [2000][2]u32 = undefined;

    for (0..100) |_| {
        const g = try arena.allocator().create(G);
        @memset(std.mem.asBytes(g), 0xAA);
        g.* = .{};

        const lim = rng.intRangeAtMost(u32, 10, 255);
        const num = rng.intRangeAtMost(u32, 0, 1999);
        var count: usize = 0;

        while (count < num) {
            const u = rng.intRangeAtMost(u32, 0, lim - 2);
            const v = rng.intRangeAtMost(u32, u + 1, lim - 1);
            _ = try g.add(u, v);
            edges[count] = .{ u, v };
            count += 1;
        }

        const result = try g.resolve();
        var pos = [_]usize{0} ** 256;
        for (result, 0..) |id, i| pos[id] = i;

        for (0..count) |i| {
            const src = edges[i][0];
            const dst = edges[i][1];
            try testing.expect(pos[src] < pos[dst]);
        }
        _ = arena.reset(.retain_capacity);
    }
}

test "diamond" {
    var g = graph.Graph(u32, 20, 50){};
    _ = try g.add(0, 1);
    _ = try g.add(0, 2);
    _ = try g.add(1, 3);
    _ = try g.add(2, 3);
    _ = try g.add(10, 11);
    _ = try g.add(11, 12);
    _ = try g.add(5, 6);
    _ = try g.add(5, 7);
    _ = try g.add(6, 8);
    _ = try g.add(7, 8);

    const result = try g.resolve();
    try testing.expectEqual(g.n, result.len);
    try order(result, 0, 1);
    try order(result, 0, 2);
    try order(result, 1, 3);
    try order(result, 2, 3);
    try order(result, 10, 11);
    try order(result, 11, 12);
    try order(result, 5, 6);
    try order(result, 5, 7);
    try order(result, 6, 8);
    try order(result, 7, 8);
}

test "cycles" {
    var g = graph.Graph(u32, 10, 20){};
    g = .{};
    _ = try g.add(1, 1);
    try testing.expectError(error.CycleDetected, g.resolve());

    g = .{};
    _ = try g.add(1, 2);
    _ = try g.add(2, 1);
    try testing.expectError(error.CycleDetected, g.resolve());

    g = .{};
    _ = try g.add(1, 2);
    _ = try g.add(2, 3);
    _ = try g.add(3, 4);
    _ = try g.add(4, 1);
    try testing.expectError(error.CycleDetected, g.resolve());
}

test "capacity" {
    var g = graph.Graph(u32, 5, 4){};
    _ = try g.add(0, 1);
    _ = try g.add(1, 2);
    _ = try g.add(2, 3);
    _ = try g.add(3, 4);

    const res = try g.resolve();
    try testing.expectEqual(@as(usize, 5), res.len);
    try order(res, 0, 4);
}

test "overflow" {
    var g = graph.Graph(u32, 10, 5){};
    try testing.expectError(error.Overflow, g.add(10, 1));
    try testing.expectError(error.Overflow, g.add(0, 10));

    _ = try g.add(0, 1);
    _ = try g.add(0, 2);
    _ = try g.add(0, 3);
    _ = try g.add(0, 4);
    _ = try g.add(0, 5);
    try testing.expectError(error.Overflow, g.add(0, 6));
    try testing.expectEqual(@as(u32, 5), g.high);
}

test "remove" {
    var g = graph.Graph(u32, 10, 10){};
    const e1 = try g.add(0, 1);
    const e2 = try g.add(1, 2);

    try testing.expectEqual(@as(u32, 1), g.refs[1]);
    try testing.expectEqual(@as(u32, 1), g.refs[2]);

    g.remove(e1, 0);
    try testing.expectEqual(@as(u32, 0), g.refs[1]);

    const sorted = try g.resolve();
    try testing.expectEqual(@as(usize, 3), sorted.len);
    
    try order(sorted, 1, 2);

    g.remove(e2, 1);
    try testing.expectEqual(@as(u32, 0), g.refs[2]);
}

test "remove reuse" {
    var g = graph.Graph(u32, 10, 5){};
    const e1 = try g.add(0, 1);
    const e2 = try g.add(0, 2);
    _ = try g.add(0, 3);
    _ = try g.add(0, 4);
    _ = try g.add(0, 5);

    try testing.expectEqual(@as(u32, 5), g.high);
    try testing.expectError(error.Overflow, g.add(0, 6));

    g.remove(e1, 0);
    g.remove(e2, 0);

    const e3 = try g.add(1, 6);
    const e4 = try g.add(1, 7);
    try testing.expectEqual(@as(u32, 5), g.high);
    try testing.expect(e3 == e1 or e3 == e2);
    try testing.expect(e4 == e1 or e4 == e2);
}

fn order(list: []const u32, before: u32, after: u32) !void {
    var b: ?usize = null;
    var a: ?usize = null;
    for (list, 0..) |id, i| {
        if (id == before) b = i;
        if (id == after) a = i;
    }
    try testing.expect(b != null and a != null and b.? < a.?);
}

test "bench small" {
    const ns_ms: i128 = 1_000_000;
    var g = graph.Graph(u32, 10000, 20000){};

    const t1 = std.time.nanoTimestamp();
    for (0..9999) |i| {
        _ = try g.add(@intCast(i), @intCast(i + 1));
    }
    const t2 = std.time.nanoTimestamp();
    _ = try g.resolve();
    const t3 = std.time.nanoTimestamp();

    const add_ms = @divTrunc(t2 - t1, ns_ms);
    const sort_ms = @divTrunc(t3 - t2, ns_ms);
    std.debug.print("\n10k: add={}ms sort={}ms\n", .{ add_ms, sort_ms });
}

test "bench large" {
    const ns_ms: i128 = 1_000_000;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const g = try arena.allocator().create(graph.Graph(u32, 1000000, 2000000));
    g.* = .{};

    const t1 = std.time.nanoTimestamp();
    for (0..999999) |i| {
        _ = try g.add(@intCast(i), @intCast(i + 1));
    }
    const t2 = std.time.nanoTimestamp();
    _ = try g.resolve();
    const t3 = std.time.nanoTimestamp();

    const add_ms = @divTrunc(t2 - t1, ns_ms);
    const sort_ms = @divTrunc(t3 - t2, ns_ms);
    std.debug.print("1M: add={}ms sort={}ms\n", .{ add_ms, sort_ms });
}
