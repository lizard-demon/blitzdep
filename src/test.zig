const std = @import("std");
const testing = std.testing;
const blitzdep = @import("blitzdep");
const Graph = blitzdep.Graph;

// === Correctness Tests ===

test "chain" {
    var g = Graph(u32, 10, 20){};
    _ = try g.add(0, 1);
    _ = try g.add(1, 2);
    _ = try g.add(3, 1);

    const sorted = try g.resolve();
    var pos = [_]usize{0} ** 4;
    for (sorted, 0..) |id, i| {
        if (id < 4) pos[id] = i;
    }

    try testing.expect(pos[0] < pos[1]);
    try testing.expect(pos[1] < pos[2]);
    try testing.expect(pos[3] < pos[1]);
}

test "diamond" {
    var g = Graph(u32, 20, 50){};
    _ = try g.add(0, 1);
    _ = try g.add(0, 2);
    _ = try g.add(1, 3);
    _ = try g.add(2, 3);

    const result = try g.resolve();
    try order(result, 0, 1);
    try order(result, 0, 2);
    try order(result, 1, 3);
    try order(result, 2, 3);
}

test "cycles" {
    var g = Graph(u32, 10, 20){};
    
    _ = try g.add(1, 1);
    try testing.expectError(error.CycleDetected, g.resolve());

    g = .{};
    _ = try g.add(1, 2);
    _ = try g.add(2, 1);
    try testing.expectError(error.CycleDetected, g.resolve());

    g = .{};
    _ = try g.add(1, 2);
    _ = try g.add(2, 3);
    _ = try g.add(3, 1);
    try testing.expectError(error.CycleDetected, g.resolve());
}

test "del" {
    var g = Graph(u32, 10, 10){};
    const e1 = try g.add(0, 1);
    const e2 = try g.add(1, 2);

    try testing.expectEqual(@as(u32, 1), g.refs[1]);
    try testing.expectEqual(@as(u32, 1), g.refs[2]);

    g.del(e1, 0);
    try testing.expectEqual(@as(u32, 0), g.refs[1]);

    const sorted = try g.resolve();
    try order(sorted, 1, 2);

    g.del(e2, 1);
    try testing.expectEqual(@as(u32, 0), g.refs[2]);
}

test "reuse" {
    var g = Graph(u32, 10, 5){};
    const e1 = try g.add(0, 1);
    const e2 = try g.add(0, 2);
    _ = try g.add(0, 3);
    _ = try g.add(0, 4);
    _ = try g.add(0, 5);

    try testing.expectEqual(@as(u32, 5), g.high);
    try testing.expectError(error.Overflow, g.add(0, 6));

    g.del(e1, 0);
    g.del(e2, 0);

    const e3 = try g.add(1, 6);
    const e4 = try g.add(1, 7);
    try testing.expectEqual(@as(u32, 5), g.high);
    try testing.expect(e3 == e1 or e3 == e2);
    try testing.expect(e4 == e1 or e4 == e2);
}

test "overflow" {
    var g = Graph(u32, 10, 5){};
    try testing.expectError(error.Overflow, g.add(10, 1));
    try testing.expectError(error.Overflow, g.add(0, 10));
}

test "comptime" {
    comptime {
        @setEvalBranchQuota(50000);
        var g = Graph(u32, 2000, 4000){};
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

test "fuzz" {
    var prng = std.Random.DefaultPrng.init(0x12345678);
    const rng = prng.random();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const G = Graph(u32, 256, 2000);
    var edges: [2000][2]u32 = undefined;

    for (0..100) |_| {
        const g = try arena.allocator().create(G);
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

        for (0..count) |i| try testing.expect(pos[edges[i][0]] < pos[edges[i][1]]);
        _ = arena.reset(.retain_capacity);
    }
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

// === Performance Tests ===

test "perf" {
    std.debug.print("\n", .{});
    try bench(10000, 1, 50);
    try bench(100000, 1, 50);
    try bench(1000000, 1, 50);
    
    std.debug.print("\n", .{});
    try bench(100000, 10, 50);
    try bench(1000000, 10, 50);
    
    std.debug.print("\n", .{});
    try bench(100000, 100, 50);
    try bench(1000000, 100, 50);
    
    std.debug.print("\n", .{});
    try bench(100000, 1000, 10);
    try bench(1000000, 1000, 10);
    
    std.debug.print("\n", .{});
    try bench(1000000, 10000, 50);
}

fn bench(comptime nodes: u32, comptime branch: u32, reps: u32) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    
    // For chain: 0→1→2→...→(N-1) uses N nodes, N-1 edges
    // For branch B: batches of B nodes, each batch has B edges
    const batches = if (branch == 1) 1 else nodes / branch - 1;
    const edges = if (branch == 1) nodes - 1 else batches * branch;
    const actual_nodes = if (branch == 1) nodes else batches * branch + branch;
    
    const G = Graph(u32, nodes, edges);
    
    var add_total: i128 = 0;
    var del_total: i128 = 0;
    var sort_total: i128 = 0;
    
    const edge_ids = try alloc.alloc(u32, edges);
    
    for (0..reps) |_| {
        const g = try alloc.create(G);
        g.* = .{};
        
        const t1 = std.time.nanoTimestamp();
        if (branch == 1) {
            for (0..nodes - 1) |i| {
                edge_ids[i] = try g.add(@intCast(i), @intCast(i + 1));
            }
        } else {
            var idx: usize = 0;
            for (0..batches) |b| {
                const base = b * branch;
                for (1..branch + 1) |j| {
                    edge_ids[idx] = try g.add(@intCast(base), @intCast(base + j));
                    idx += 1;
                }
            }
        }
        const t2 = std.time.nanoTimestamp();
        _ = try g.resolve();
        const t3 = std.time.nanoTimestamp();
        
        for (0..edges) |i| {
            g.del(edge_ids[i], @intCast(if (branch == 1) i else (i / branch) * branch));
        }
        const t4 = std.time.nanoTimestamp();
        
        add_total += t2 - t1;
        sort_total += t3 - t2;
        del_total += t4 - t3;
    }
    
    const add_ms = @divTrunc(add_total, reps * 1_000_000);
    const sort_ms = @divTrunc(sort_total, reps * 1_000_000);
    const del_ms = @divTrunc(del_total, reps * 1_000_000);
    const total_ms = add_ms + sort_ms;
    
    const nodes_per_sec = if (total_ms > 0) @divTrunc(actual_nodes * 1000, @as(u32, @intCast(total_ms))) else 0;
    const ns_per_node = if (total_ms > 0) @divTrunc(total_ms * 1_000_000, actual_nodes) else 0;
    
    std.debug.print(" Add       {d:7} nodes {d:6} edges, time: {d:4}ms, {d:8} nodes/s, {d:5} ns/node\n", 
        .{ actual_nodes, edges, add_ms, if (add_ms > 0) @divTrunc(actual_nodes * 1000, @as(u32, @intCast(add_ms))) else 0, 
           if (add_ms > 0) @divTrunc(add_ms * 1_000_000, actual_nodes) else 0 });
    std.debug.print(" Sort      {d:7} nodes {d:6} edges, time: {d:4}ms, {d:8} nodes/s, {d:5} ns/node\n", 
        .{ actual_nodes, edges, sort_ms, if (sort_ms > 0) @divTrunc(actual_nodes * 1000, @as(u32, @intCast(sort_ms))) else 0,
           if (sort_ms > 0) @divTrunc(sort_ms * 1_000_000, actual_nodes) else 0 });
    std.debug.print(" Remove    {d:7} nodes {d:6} edges, time: {d:4}ms, {d:8} nodes/s, {d:5} ns/node\n", 
        .{ actual_nodes, edges, del_ms, if (del_ms > 0) @divTrunc(actual_nodes * 1000, @as(u32, @intCast(del_ms))) else 0,
           if (del_ms > 0) @divTrunc(del_ms * 1_000_000, actual_nodes) else 0 });
    std.debug.print(" Add+Sort  {d:7} nodes {d:6} edges, time: {d:4}ms, {d:8} nodes/s, {d:5} ns/node\n", 
        .{ actual_nodes, edges, total_ms, nodes_per_sec, ns_per_node });
}
