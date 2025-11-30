const std = @import("std");
const testing = std.testing;
const Graph = @import("blitzdep").Graph;

// -------------------------------------------------------------------------
// 1. Internal Integrity Tests (Targeted Debugging)
// -------------------------------------------------------------------------

test "internals: verify initialization (ReleaseFast check)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const GType = Graph(u32, 100, 200);
    
    // Run multiple times to encourage memory reuse checks
    for (0..20) |_| {
        const g = try allocator.create(GType);
        
        // Fill with garbage first to simulate dirty stack/heap
        @memset(std.mem.asBytes(g), 0xAA);
        
        // Initialize
        g.* = .{};

        try testing.expectEqual(@as(u32, 0), g.node_n);
        try testing.expectEqual(@as(u32, 0), g.edge_n);

        for (g.node, 0..) |n, i| {
            if (n != null) {
                std.debug.print("\nFAIL: node[{}] is not null! Value: {?}\n", .{i, n});
                return error.InitializationFailed;
            }
        }
    }
}

test "internals: verify graph structure fidelity" {
    var g = Graph(u32, 50, 50){};
    
    _ = g.add(0, .{1});
    _ = g.add(0, .{2});
    _ = g.add(1, .{3});

    try testing.expectEqual(@as(u32, 3), g.edge_n);
    
    var seen_1 = false;
    var seen_2 = false;
    var count_0: usize = 0;
    
    var iter = g.node[0];
    while (iter) |e_idx| {
        count_0 += 1;
        const target = g.edge[e_idx];
        if (target == 1) seen_1 = true;
        if (target == 2) seen_2 = true;
        iter = g.next[e_idx];
    }
    
    if (!seen_1 or !seen_2 or count_0 != 2) return error.StructureCorrupted;

    var seen_3 = false;
    iter = g.node[1];
    while (iter) |e_idx| {
        if (g.edge[e_idx] == 3) seen_3 = true;
        iter = g.next[e_idx];
    }
    
    if (!seen_3) return error.StructureCorrupted;
}

test "internals: manual degree calculation check" {
    var g = Graph(u32, 10, 10){};
    
    _ = g.add(0, .{2});
    _ = g.add(1, .{2});
    
    _ = try g.resolve();
    
    var deg_2: u32 = 0;
    for (0..g.node_n) |i| {
        var it = g.node[i];
        while (it) |e| {
            if (g.edge[e] == 2) deg_2 += 1;
            it = g.next[e];
        }
    }
    
    try testing.expectEqual(@as(u32, 2), deg_2);
}

// -------------------------------------------------------------------------
// 2. Fuzz Testing
// -------------------------------------------------------------------------

test "fuzz: random acyclic graph validation" {
    var prng = std.Random.DefaultPrng.init(0x12345678);
    const random = prng.random();
    
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const NODE_MAX = 256;
    const EDGE_MAX = 2000;
    const ITERATIONS = 100;
    const GType = Graph(u32, NODE_MAX, EDGE_MAX);

    var verify_edges: [EDGE_MAX][2]u32 = undefined;

    for (0..ITERATIONS) |iter| {
        _ = iter;
        
        const g = try allocator.create(GType);
        // Explicit memset to catch init bugs
        @memset(std.mem.asBytes(g), 0xAA);
        g.* = .{}; 

        const num_nodes_limit = random.intRangeAtMost(u32, 10, NODE_MAX - 1);
        const num_edges = random.intRangeAtMost(u32, 0, EDGE_MAX - 1);
        var edge_count: usize = 0;
        
        // FIX: Track the actual Max Node ID seen. 
        // The Graph auto-sizes to max_id + 1, not the RNG limit.
        var max_seen_id: u32 = 0;
        var has_nodes = false;

        while (edge_count < num_edges) {
            const u = random.intRangeAtMost(u32, 0, num_nodes_limit - 2);
            const v = random.intRangeAtMost(u32, u + 1, num_nodes_limit - 1); 

            _ = g.add(u, .{v});
            verify_edges[edge_count] = .{ u, v };
            edge_count += 1;
            
            if (u > max_seen_id) max_seen_id = u;
            if (v > max_seen_id) max_seen_id = v;
            has_nodes = true;
        }

        const result = try g.resolve();

        // FIX: Assert against the actual max_seen_id, not the random limit.
        if (has_nodes) {
            try testing.expect(result.len >= max_seen_id + 1);
        } else {
            try testing.expect(result.len == 0);
        }

        var pos_map = [_]usize{0} ** NODE_MAX;
        for (result, 0..) |node_id, index| {
            pos_map[node_id] = index;
        }

        for (0..edge_count) |i| {
            const src = verify_edges[i][0];
            const dst = verify_edges[i][1];
            
            const src_pos = pos_map[src];
            const dst_pos = pos_map[dst];

            if (src_pos >= dst_pos) {
                std.debug.print("\nFAIL: Edge {}->{} violated. Result order: {any}\n", .{src, dst, result});
                return error.TopologyConstraintViolated;
            }
        }
        
        _ = arena.reset(.retain_capacity);
    }
}

// -------------------------------------------------------------------------
// 3. Structural Robustness
// -------------------------------------------------------------------------

test "robust: complex structures" {
    var g = Graph(u32, 20, 50){};
    _ = g.add(0, .{ 1, 2 });
    _ = g.add(1, .{3});
    _ = g.add(2, .{3});
    _ = g.add(10, .{11});
    _ = g.add(11, .{12});
    _ = g.add(5, .{ 6, 7 });
    _ = g.add(6, .{8});
    _ = g.add(7, .{8});

    const result = try g.resolve();
    try testing.expectEqual(g.node_n, result.len);
    try assertOrder(result, 0, 1);
    try assertOrder(result, 0, 2);
    try assertOrder(result, 1, 3);
    try assertOrder(result, 2, 3);
    try assertOrder(result, 10, 11);
    try assertOrder(result, 11, 12);
    try assertOrder(result, 5, 6);
    try assertOrder(result, 5, 7);
    try assertOrder(result, 6, 8);
    try assertOrder(result, 7, 8);
}

test "robust: extreme cycles" {
    var g = Graph(u32, 10, 20){};
    g = .{}; _ = g.add(1, .{1}); try testing.expectError(error.CycleDetected, g.resolve());
    g = .{}; _ = g.add(1, .{2}); _ = g.add(2, .{1}); try testing.expectError(error.CycleDetected, g.resolve());
    g = .{}; _ = g.add(1, .{2}); _ = g.add(2, .{3}); _ = g.add(3, .{4}); _ = g.add(4, .{1}); try testing.expectError(error.CycleDetected, g.resolve());
}

test "robust: max capacity saturation" {
    var g = Graph(u32, 5, 4){};
    _ = g.add(0, .{1}); _ = g.add(1, .{2}); _ = g.add(2, .{3}); _ = g.add(3, .{4});
    const res = try g.resolve();
    try testing.expectEqual(@as(usize, 5), res.len);
    try assertOrder(res, 0, 4);
}

fn assertOrder(list: []const u32, before: u32, after: u32) !void {
    var idx_before: ?usize = null;
    var idx_after: ?usize = null;

    for (list, 0..) |item, i| {
        if (item == before) idx_before = i;
        if (item == after) idx_after = i;
    }
    if (idx_before == null or idx_after == null) return error.NodeNotFound;
    if (idx_before.? >= idx_after.?) return error.OrderViolated;
}
