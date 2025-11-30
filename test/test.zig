const std = @import("std");
const testing = std.testing;
// CHANGED: Import from named module instead of relative path
const Graph = @import("blitzdep").Graph;

// -----------------------------------------------------------------------------
// Global Graph Instances
// -----------------------------------------------------------------------------
var g1k: Graph(u32, 1_000, 10_000) = .{};
var g10k: Graph(u32, 10_000, 100_000) = .{};
var g100k: Graph(u32, 100_000, 1_000_000) = .{};
var g1m: Graph(u32, 1_000_000, 10_000_000) = .{};

// -----------------------------------------------------------------------------
// Benchmark Harness
// -----------------------------------------------------------------------------

pub fn benchmark(N: usize, B: usize, comptime M: bool, comptime R: usize,
                 options: struct {
                     add: bool = false,
                     sort: bool = false,
                     total: bool = true, }) !void {
    _ = M; 

    var add_times:  [R]Timing = [1]Timing{ .{} } ** R;
    var sort_times: [R]Timing = [1]Timing{ .{} } ** R;

    for (0..R) |i| {
        const res = if (N <= 1_000) try run_cycle(&g1k, N, B)
            else if (N <= 10_000) try run_cycle(&g10k, N, B)
            else if (N <= 100_000) try run_cycle(&g100k, N, B)
            else try run_cycle(&g1m, N, B);
        
        add_times[i] = res.add;
        sort_times[i] = res.sort;
    }

    const add_total = compute_total(N, B, R, add_times);
    const sort_total = compute_total(N, B, R, sort_times);
    var total = compute_total(N, B, R, sort_times);
    total.add(add_total);

    if (options.add)    try add_total.print("   Add dep");
    if (options.sort)   try sort_total.print("      Sort");
    if (options.total)  try total.print("Add + Sort");
}

fn run_cycle(g: anytype, N: usize, B: usize) !struct { add: Timing, sort: Timing } {
    g.* = .{}; // Reset

    const start1 = std.time.nanoTimestamp();
    const batch: usize = N / B; 
    
    for (0..batch) |b_idx| {
        const base: u32 = @intCast(b_idx * B);
        for (1..B) |j| {
            _ = g.add(base, .{base + @as(u32, @intCast(j))});
        }
        _ = g.add(base, .{base + @as(u32, @intCast(B))});
    }
    const end1 = std.time.nanoTimestamp();

    const start2 = std.time.nanoTimestamp();
    _ = g.resolve() catch {};
    const end2 = std.time.nanoTimestamp();

    return .{
        .add = .{ .n = N, .b = B, .start_ns = start1, .end_ns = end1 },
        .sort = .{ .n = N, .b = B, .start_ns = start2, .end_ns = end2 },
    };
}

// -----------------------------------------------------------------------------
// Formatting & Helpers
// -----------------------------------------------------------------------------

const NS_TO_MS = 1000 * 1000;

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
    fn ns_per_item(self: Timing) i128 { return @divTrunc(self.elapsed_ns(), @as(i128, @intCast(self.n))); }
};

const TimeTotal = struct {
    n:          usize = 0,
    b:          usize = 0,
    repeat:     usize = 0,
    total:      usize = 0,
    elapsed_ns: i128 = 0,

    fn elapsed_ms(self: TimeTotal) i128 { return @divTrunc(self.elapsed_ns, NS_TO_MS); }
    fn ms_per_n(self: TimeTotal) i128 { return @divTrunc(self.elapsed_ms(), @as(i128, @intCast(self.repeat))); }
    fn nps(self: TimeTotal) i128 { 
        if (self.elapsed_ns == 0) return 0;
        return @divTrunc(@as(i128, @intCast(self.total)) * NS_TO_MS * 1000, self.elapsed_ns); 
    }
    fn ns_per_item(self: TimeTotal) i128 { return @divTrunc(self.elapsed_ns, @as(i128, @intCast(self.total))); }
    
    fn print(self: TimeTotal, title: []const u8) !void {
        var buf1: [128]u8 = undefined;
        var buf2: [128]u8 = undefined;
        var buf3: [128]u8 = undefined;
        var buf4: [128]u8 = undefined;
        
        const str1 = try fmtInt(i128, self.elapsed_ms(), 6, &buf1); 
        const str2 = try fmtInt(i128, self.ms_per_n(), 5, &buf2);
        const str3 = try fmtInt(i128, self.nps(), 9, &buf3);
        const str4 = try fmtInt(i128, self.ns_per_item(), 6, &buf4);
        
        std.debug.print("{s:11} {:8} nodes {:6} links, repeat{: >2}, time:{s}ms,{s} nodes/s,{s} ns/node.\n",
                        .{title, self.n, self.b, self.repeat, str2, str3, str4 });
        _ = str1; 
    }

    fn add(self: *TimeTotal, from: TimeTotal) void {
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
    std.mem.replaceScalar(u8, str, '+', ' ');
    return str;
}

// -----------------------------------------------------------------------------
// Test Execution Block
// -----------------------------------------------------------------------------

test {
    std.debug.print("\nBenchmark increasing node in 10X scale on branching 1, no max_range\n", .{});
    try benchmark(10000, 1, false, 6, .{ .add = true, .sort = true, .total = false });
    try benchmark(100000, 1, false, 6, .{ .add = true, .sort = true, .total = false });
    try benchmark(1000000, 1, false, 6, .{ .add = true, .sort = true, .total = false });

    std.debug.print("\nBenchmark increasing node in 10X scale on branching 1, with max_range\n", .{});
    try benchmark(10000, 1, true, 6, .{ .add = true, .sort = true, .total = false });
    try benchmark(100000, 1, true, 6, .{ .add = true, .sort = true, .total = false });
    try benchmark(1000000, 1, true, 6, .{ .add = true, .sort = true, .total = false });

    std.debug.print("\nBenchmark increasing nodes on fixed branching, with max_range\n", .{});
    try benchmark(10000, 1000, true, 6, .{ .total = true });
    try benchmark(20000, 1000, true, 6, .{ .total = true });
    try benchmark(30000, 1000, true, 6, .{ .total = true });
    try benchmark(40000, 1000, true, 6, .{ .total = true });
    try benchmark(50000, 1000, true, 6, .{ .total = true });
    try benchmark(100000, 1000, true, 6, .{ .total = true });
    try benchmark(200000, 1000, true, 6, .{ .total = true });
    try benchmark(300000, 1000, true, 6, .{ .total = true });
    try benchmark(400000, 1000, true, 6, .{ .total = true });
    try benchmark(500000, 1000, true, 6, .{ .total = true });
    try benchmark(600000, 1000, true, 6, .{ .total = true });
    try benchmark(700000, 1000, true, 6, .{ .total = true });
    try benchmark(800000, 1000, true, 6, .{ .total = true });
    try benchmark(900000, 1000, true, 6, .{ .total = true });
    try benchmark(1000000, 1000, true, 6, .{ .total = true });

    std.debug.print("\nBenchmark increasing node and increasing link branching, with max_range\n", .{});
    try benchmark(10000, 2, true, 6, .{ .total = true });
    try benchmark(100000, 2, true, 6, .{ .total = true });
    try benchmark(1000000, 2, true, 6, .{ .total = true });

    try benchmark(10000, 10, true, 6, .{});
    try benchmark(100000, 10, true, 6, .{});
    try benchmark(1000000, 10, true, 6, .{});

    try benchmark(10000, 100, true, 6, .{});
    try benchmark(100000, 100, true, 6, .{});
    try benchmark(1000000, 100, true, 6, .{});

    try benchmark(10000, 1000, true, 6, .{});
    try benchmark(100000, 1000, true, 6, .{});
    try benchmark(1000000, 1000, true, 6, .{});

    try benchmark(10000, 2000, true, 6, .{});
    try benchmark(100000, 2000, true, 6, .{});
    try benchmark(1000000, 2000, true, 6, .{});

    try benchmark(10000, 3000, true, 6, .{});
    try benchmark(100000, 3000, true, 6, .{});
    try benchmark(1000000, 3000, true, 6, .{});

    try benchmark(10000, 4000, true, 6, .{});
    try benchmark(100000, 4000, true, 6, .{});
    try benchmark(1000000, 4000, true, 6, .{});

    try benchmark(10000, 5000, true, 6, .{});
    try benchmark(100000, 5000, true, 6, .{});
    try benchmark(1000000, 5000, true, 6, .{});

    std.debug.print("\nBenchmark increasing large link branching, with max_range\n", .{});
    try benchmark(1000000, 100, true, 3, .{});
    try benchmark(1000000, 200, true, 3, .{});
    try benchmark(1000000, 300, true, 3, .{});
    try benchmark(1000000, 400, true, 3, .{});
    try benchmark(1000000, 500, true, 3, .{});
    try benchmark(1000000, 600, true, 3, .{});
    
    try benchmark(1000000, 1000, true, 3, .{});
    try benchmark(1000000, 2000, true, 3, .{});
    try benchmark(1000000, 3000, true, 3, .{});
    try benchmark(1000000, 4000, true, 3, .{});
    try benchmark(1000000, 5000, true, 3, .{});
    try benchmark(1000000, 6000, true, 3, .{});
    
    try benchmark(1000000, 10000, true, 3, .{});
    try benchmark(1000000, 20000, true, 3, .{});
    try benchmark(1000000, 30000, true, 3, .{});
    try benchmark(1000000, 40000, true, 3, .{});
    try benchmark(1000000, 50000, true, 3, .{});
    try benchmark(1000000, 60000, true, 3, .{});
    
    try benchmark(1000000, 100000, true, 3, .{});
    try benchmark(1000000, 200000, true, 3, .{});
    try benchmark(1000000, 300000, true, 3, .{});
    try benchmark(1000000, 400000, true, 3, .{});
    try benchmark(1000000, 500000, true, 3, .{});
}
