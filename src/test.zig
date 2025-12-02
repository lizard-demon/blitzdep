const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const zdep = @import("blitzdep");
const Graph = zdep.Graph;

// -------------------------------------------------------------------------
// Unit Tests & Coverage
// -------------------------------------------------------------------------

test "comptime: topological sort" {
    std.debug.print("\n[TEST] comptime: topological sort\n", .{});
    comptime {
        const MyComptimeGraph = zdep.Graph(u32, 10, 20);
        var g = MyComptimeGraph{ .node_n = 0, .edge_n = 0 }; 
        
        _ = g.add(0, .{1}) catch unreachable;
        _ = g.add(1, .{2}) catch unreachable;
        _ = g.add(3, .{1}) catch unreachable;
        _ = g.add(4, .{}) catch unreachable;

        const sorted = g.resolve() catch unreachable;

        var pos_map = [_]usize{0} ** 5; 
        for (sorted, 0..) |node_id, index| {
            if (node_id < 5) pos_map[node_id] = index;
        }

        try testing.expect(pos_map[0] < pos_map[1]); // 0 before 1
        try testing.expect(pos_map[1] < pos_map[2]); // 1 before 2
        try testing.expect(pos_map[3] < pos_map[1]); // 3 before 1
    }
    std.debug.print("[PASS] comptime: topological sort\n", .{});
}

test "comptime: very large topological sort" {
    std.debug.print("\n[TEST] comptime: very large topological sort (2000 nodes)\n", .{});
    comptime {
        @setEvalBranchQuota(50000);
        const NODE_COUNT = 2000;
        const EDGE_COUNT = 4000;
        const MyComptimeGraph = zdep.Graph(u32, NODE_COUNT, EDGE_COUNT);
        var g = MyComptimeGraph{}; 

        var i: u32 = 0;
        while (i < NODE_COUNT - 1) : (i += 1) {
            _ = try g.add(i, .{i + 1});
        }

        const sorted = g.resolve() catch unreachable;
        try testing.expectEqual(@as(usize, NODE_COUNT), sorted.len);
        i = 0;
        while (i < sorted.len) : (i += 1) {
            try testing.expectEqual(i, sorted[i]);
        }
    }
    std.debug.print("[PASS] comptime: very large topological sort\n", .{});
}

test "internals: verify initialization (ReleaseFast check)" {
    std.debug.print("\n[TEST] internals: verify initialization (20 iterations)\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const GType = zdep.Graph(u32, 100, 200);
    
    for (0..20) |iteration| {
        const g = try allocator.create(GType);
        @memset(std.mem.asBytes(g), 0xAA); // Fill with garbage
        g.* = .{}; // Initialize

        try testing.expectEqual(@as(u32, 0), g.node_n);
        try testing.expectEqual(@as(u32, 0), g.edge_n);

        for (g.node, 0..) |n, i| {
            if (n != null) {
                std.debug.print("\nFAIL: node[{}] is not null! Value: {?}\n", .{i, n});
                return error.InitializationFailed;
            }
        }
        if ((iteration + 1) % 5 == 0) {
            std.debug.print("  ✓ Completed {} iterations\n", .{iteration + 1});
        }
    }
    std.debug.print("[PASS] internals: verify initialization\n", .{});
}

test "internals: verify graph structure fidelity" {
    std.debug.print("\n[TEST] internals: verify graph structure fidelity\n", .{});
    var g = zdep.Graph(u32, 50, 50){};
    
    _ = try g.add(0, .{1});
    _ = try g.add(0, .{2});
    _ = try g.add(1, .{3});

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
    std.debug.print("[PASS] internals: verify graph structure fidelity\n", .{});
}

test "internals: manual degree calculation check" {
    std.debug.print("\n[TEST] internals: manual degree calculation check\n", .{});
    var g = zdep.Graph(u32, 10, 10){};
    _ = try g.add(0, .{2});
    _ = try g.add(1, .{2});
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
    std.debug.print("[PASS] internals: manual degree calculation check\n", .{});
}

test "fuzz: random acyclic graph validation" {
    std.debug.print("\n[TEST] fuzz: random acyclic graph validation (100 iterations)\n", .{});
    var prng = std.Random.DefaultPrng.init(0x12345678);
    const random = prng.random();
    
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const NODE_MAX = 256;
    const EDGE_MAX = 2000;
    const ITERATIONS = 100;
    const GType = zdep.Graph(u32, NODE_MAX, EDGE_MAX);

    var verify_edges: [EDGE_MAX][2]u32 = undefined;

    for (0..ITERATIONS) |iteration| {
        const g = try allocator.create(GType);
        @memset(std.mem.asBytes(g), 0xAA);
        g.* = .{}; 

        const num_nodes_limit = random.intRangeAtMost(u32, 10, NODE_MAX - 1);
        const num_edges = random.intRangeAtMost(u32, 0, EDGE_MAX - 1);
        var edge_count: usize = 0;
        
        var max_seen_id: u32 = 0;
        var has_nodes = false;

        while (edge_count < num_edges) {
            const u = random.intRangeAtMost(u32, 0, num_nodes_limit - 2);
            const v = random.intRangeAtMost(u32, u + 1, num_nodes_limit - 1); 

            _ = try g.add(u, .{v});
            verify_edges[edge_count] = .{ u, v };
            edge_count += 1;
            
            if (u > max_seen_id) max_seen_id = u;
            if (v > max_seen_id) max_seen_id = v;
            has_nodes = true;
        }

        const result = try g.resolve();

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
        if ((iteration + 1) % 20 == 0) {
            std.debug.print("  ✓ Completed {} iterations\n", .{iteration + 1});
        }
        _ = arena.reset(.retain_capacity);
    }
    std.debug.print("[PASS] fuzz: random acyclic graph validation\n", .{});
}

test "robust: complex structures" {
    std.debug.print("\n[TEST] robust: complex structures\n", .{});
    var g = zdep.Graph(u32, 20, 50){};
    _ = try g.add(0, .{ 1, 2 });
    _ = try g.add(1, .{3});
    _ = try g.add(2, .{3});
    _ = try g.add(10, .{11});
    _ = try g.add(11, .{12});
    _ = try g.add(5, .{ 6, 7 });
    _ = try g.add(6, .{8});
    _ = try g.add(7, .{8});

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
    std.debug.print("[PASS] robust: complex structures\n", .{});
}

test "robust: extreme cycles" {
    std.debug.print("\n[TEST] robust: extreme cycles\n", .{});
    var g = zdep.Graph(u32, 10, 20){};
    
    std.debug.print("  Testing self-loop...\n", .{});
    g = .{}; _ = try g.add(1, .{1}); try testing.expectError(error.CycleDetected, g.resolve());
    
    std.debug.print("  Testing 2-node cycle...\n", .{});
    g = .{}; _ = try g.add(1, .{2}); _ = try g.add(2, .{1}); try testing.expectError(error.CycleDetected, g.resolve());
    
    std.debug.print("  Testing 4-node cycle...\n", .{});
    g = .{}; 
    _ = try g.add(1, .{2}); 
    _ = try g.add(2, .{3}); 
    _ = try g.add(3, .{4}); 
    _ = try g.add(4, .{1}); 
    try testing.expectError(error.CycleDetected, g.resolve());
    std.debug.print("[PASS] robust: extreme cycles\n", .{});
}

test "robust: max capacity saturation" {
    std.debug.print("\n[TEST] robust: max capacity saturation\n", .{});
    var g = zdep.Graph(u32, 5, 4){}; 
    _ = try g.add(0, .{1}); 
    _ = try g.add(1, .{2}); 
    _ = try g.add(2, .{3}); 
    _ = try g.add(3, .{4});
    
    const res = try g.resolve();
    try testing.expectEqual(@as(usize, 5), res.len);
    try assertOrder(res, 0, 4);
    std.debug.print("[PASS] robust: max capacity saturation\n", .{});
}

test "error: bounds checking" {
    std.debug.print("\n[TEST] error: bounds checking\n", .{});
    var g = zdep.Graph(u32, 10, 5){}; 
    
    std.debug.print("  Testing node overflow...\n", .{});
    try testing.expectError(error.Overflow, g.add(10, .{1})); 
    try testing.expectError(error.Overflow, g.add(0, .{10})); 

    std.debug.print("  Testing edge overflow...\n", .{});
    _ = try g.add(0, .{1}); 
    _ = try g.add(0, .{2}); 
    _ = try g.add(0, .{3}); 
    _ = try g.add(0, .{4}); 
    _ = try g.add(0, .{5}); 
    
    try testing.expectError(error.Overflow, g.add(0, .{6}));
    try testing.expectEqual(@as(u32, 5), g.edge_n);
    std.debug.print("[PASS] error: bounds checking\n", .{});
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

// -------------------------------------------------------------------------
// Benchmarking Suite
// -------------------------------------------------------------------------

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn benchmark(comptime N: usize, B: usize, comptime R: usize,
                 options: struct {
                     add: bool = false,
                     sort: bool = false,
                     total: bool = true, }) !void {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); 
    const allocator = arena.allocator();

    const T = u32;
    const EdgeMax = if (N < 100) 100 else (N * 2) + (N / 5);
    const GraphType = Graph(T, N, EdgeMax); 

    var add_times:  [R]Timing = [1]Timing{ .{} } ** R;
    var sort_times: [R]Timing = [1]Timing{ .{} } ** R;
    
    const list = try gen_int_items(N, T, allocator);

    for (0..R) |i| {
        var tsort = try allocator.create(GraphType);
        tsort.* = GraphType{}; 

        const start1 = std.time.nanoTimestamp();
        
        if (B > 0) {
            const batch: usize = if (B == 1) N - 1 else (N / B) - 1;
            
            for (0..batch) |b| {
                const base = b * B;
                if (B > 1) {
                    for (1..B) |j| {
                        _ = try tsort.add(list.items[base], .{ list.items[base + j] });
                    }
                }
                _ = try tsort.add(list.items[base], .{ list.items[base + B] }); 
            }
        }
        
        add_times[i] = .{ .n = N, .start_ns = start1, .end_ns = std.time.nanoTimestamp(), .b = B };

        const start2 = std.time.nanoTimestamp();
        _ = try tsort.resolve();
        sort_times[i] = .{ .n = N, .start_ns = start2, .end_ns = std.time.nanoTimestamp(), .b = B };
    }

    const add_total = compute_total(N, B, R, add_times);
    const sort_total = compute_total(N, B, R, sort_times);
    var total = compute_total(N, B, R, sort_times);
    total.add(add_total);

    var prefix_buf: [64]u8 = undefined;
    const prefix = try std.fmt.bufPrint(&prefix_buf, "N={d} B={d}", .{N, B});

    if (options.add)    try add_total.print(prefix);
    if (options.sort)   try sort_total.print("Sort");
    if (options.total)  try total.print(prefix);
}

pub fn benchmark_thrasher(comptime N: usize, B: usize, comptime R: usize) !void {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); 
    const allocator = arena.allocator();

    const T = u32;
    const EdgeMax = if (N < 100) 100 else (N * 2) + (N / 5);
    const GraphType = Graph(T, N, EdgeMax); 

    var add_times:  [R]Timing = [1]Timing{ .{} } ** R;
    var sort_times: [R]Timing = [1]Timing{ .{} } ** R;
    
    const list = try gen_int_items(N, T, allocator);

    var prng = std.Random.DefaultPrng.init(42); 
    const random = prng.random();
    random.shuffle(T, list.items);

    for (0..R) |i| {
        var tsort = try allocator.create(GraphType);
        tsort.* = GraphType{}; 

        const start1 = std.time.nanoTimestamp();
        
        if (B > 0) {
            const batch: usize = if (B == 1) N - 1 else (N / B) - 1;
            
            for (0..batch) |b| {
                const base = b * B;
                if (B > 1) {
                    for (1..B) |j| {
                        _ = try tsort.add(list.items[base], .{ list.items[base + j] });
                    }
                }
                _ = try tsort.add(list.items[base], .{ list.items[base + B] }); 
            }
        }
        add_times[i] = .{ .n = N, .start_ns = start1, .end_ns = std.time.nanoTimestamp(), .b = B };

        const start2 = std.time.nanoTimestamp();
        _ = try tsort.resolve();
        sort_times[i] = .{ .n = N, .start_ns = start2, .end_ns = std.time.nanoTimestamp(), .b = B };
    }

    const add_total = compute_total(N, B, R, add_times);
    var total = compute_total(N, B, R, sort_times);
    total.add(add_total);

    var prefix_buf: [64]u8 = undefined;
    const prefix = try std.fmt.bufPrint(&prefix_buf, "THRASH N={d} B={d}", .{N, B});
    try total.print(prefix);
}

fn gen_int_items(N: usize, comptime T: type, allocator: Allocator) !ArrayList(T) {
    var list = try ArrayList(T).initCapacity(allocator, N);
    for (0..N) |num| {
        list.appendAssumeCapacity(@intCast(num));
    }
    return list;
}

const NS_TO_MS: i128 = 1000 * 1000;

const Timing = struct {
    n:          usize = 0,
    b:          usize = 0,
    start_ns:   i128 = 0,
    end_ns:     i128 = 0,

    fn elapsed_ns(self: Timing) i128 { return self.end_ns - self.start_ns; }
    fn elapsed_ms(self: Timing) i128 { return @divTrunc(self.elapsed_ns(), NS_TO_MS); }
    fn nps(self: Timing) i128 { 
        if (self.elapsed_ns() == 0) return 0;
        return @divTrunc(@as(i128, @intCast(self.n)) * NS_TO_MS * 1000, self.elapsed_ns()); 
    }
    fn ns_per_item(self: Timing) i128 { 
        if (self.n == 0) return 0;
        return @divTrunc(self.elapsed_ns(), @as(i128, @intCast(self.n))); 
    }
};

const TimeTotal = struct {
    n:          usize = 0,
    b:          usize = 0,
    repeat:     usize = 0,
    total:      usize = 0,
    elapsed_ns: i128 = 0,

    fn elapsed_ms(self: TimeTotal) i128 { return @divTrunc(self.elapsed_ns, NS_TO_MS); }
    fn ms_per_n(self: TimeTotal) i128 { 
        if (self.repeat == 0) return 0;
        return @divTrunc(self.elapsed_ms(), @as(i128, @intCast(self.repeat))); 
    }
    fn nps(self: TimeTotal) i128 { 
        if (self.elapsed_ns == 0) return 0;
        return @divTrunc(@as(i128, @intCast(self.total)) * NS_TO_MS * 1000, self.elapsed_ns); 
    }
    fn ns_per_item(self: TimeTotal) i128 { 
        if (self.total == 0) return 0;
        return @divTrunc(self.elapsed_ns, @as(i128, @intCast(self.total))); 
    }
    fn print(self: TimeTotal, title: []const u8) !void {
        var buf2: [128]u8 = undefined;
        var buf3: [128]u8 = undefined;
        var buf4: [128]u8 = undefined;
        const str2 = try fmtInt(i128, self.ms_per_n(), 5, &buf2);
        const str3 = try fmtInt(i128, self.nps(), 9, &buf3);
        const str4 = try fmtInt(i128, self.ns_per_item(), 6, &buf4);
        std.debug.print("{s:18} | Time:{s}ms | {s} nodes/s | {s} ns/node\n",
                        .{title, str2, str3, str4 });
    }

    fn add(self: *TimeTotal, from: TimeTotal) void {
        self.total += from.total;
        self.elapsed_ns += from.elapsed_ns;
    }
};

fn compute_total(N: usize, B: usize, comptime R: usize, times: [R]Timing) TimeTotal {
    var total: TimeTotal = .{ .n = N, .b = B, };
    var max: i128 = times[0].elapsed_ns();
    var max_i: usize = 0;

    for (1..R)|i| {
        if (max < times[i].elapsed_ns()) {
            max = times[i].elapsed_ns();
            max_i = i;
        }
    }
    for (0..R)|i| {
        if (R > 1 and i == max_i) continue;     
        total.repeat += 1;
        total.total += times[i].n;
        total.elapsed_ns += times[i].elapsed_ns();
    }
    return total;
}

pub fn fmtInt(comptime T: type, num: T, width: usize, buf: []u8) ![]u8 {
    const str = try std.fmt.bufPrint(buf, "{[value]: >[width]}", .{.value = num, .width = width});
    _ = std.mem.replaceScalar(u8, str, '+', ' ');   
    return str;
}

test "Benchmarks" {
    std.debug.print("\nBenchmark increasing node in 10X scale on branching 1\n", .{});
    try benchmark(10000, 1, 6, .{ .add = true, .sort = true, .total = false });
    try benchmark(100000, 1, 6, .{ .add = true, .sort = true, .total = false });
    try benchmark(1000000, 1, 6, .{ .add = true, .sort = true, .total = false });

    std.debug.print("\nBenchmark increasing nodes on fixed branching\n", .{});
    try benchmark(10000, 1000, 6, .{});
    try benchmark(20000, 1000, 6, .{});
    try benchmark(50000, 1000, 6, .{});
    try benchmark(100000, 1000, 6, .{});
    try benchmark(500000, 1000, 6, .{});
    try benchmark(1000000, 1000, 6, .{});

    std.debug.print("\nBenchmark increasing node and increasing link branching\n", .{});
    try benchmark(10000, 2, 6, .{});
    try benchmark(100000, 2, 6, .{});
    try benchmark(1000000, 2, 6, .{});

    try benchmark(10000, 10, 6, .{});
    try benchmark(100000, 10, 6, .{});
    try benchmark(1000000, 10, 6, .{});

    try benchmark(10000, 100, 6, .{});
    try benchmark(100000, 100, 6, .{});
    try benchmark(1000000, 100, 6, .{});

    try benchmark(10000, 1000, 6, .{});
    try benchmark(100000, 1000, 6, .{});
    try benchmark(1000000, 1000, 6, .{});

    std.debug.print("\nBenchmark increasing large link branching\n", .{});
    try benchmark(1000000, 100, 3, .{});
    try benchmark(1000000, 500, 3, .{});
    try benchmark(1000000, 1000, 3, .{});
    try benchmark(1000000, 5000, 3, .{});
    try benchmark(1000000, 10000, 3, .{});
    try benchmark(1000000, 50000, 3, .{});
}

test "Cache Thrasher" {
    std.debug.print("\nBenchmark: CACHE THRASHER (Randomized Memory Access)\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});

    try benchmark_thrasher(100000, 10, 6);
    try benchmark_thrasher(1000000, 10, 6);

    try benchmark_thrasher(100000, 1000, 6);
    try benchmark_thrasher(1000000, 1000, 6);

    try benchmark_thrasher(100000, 5000, 6);
    try benchmark_thrasher(1000000, 5000, 6);
}
