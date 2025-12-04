const std = @import("std");

/// High-performance statically allocated DAG for reactive systems.
/// O(1) add/del via array-backed doubly-linked lists.
pub fn Graph(comptime T: type, comptime max_nodes: u32, comptime max_edges: u32) type {
    return struct {
        n: u32 = 0,
        head: [max_nodes]?u32 = [_]?u32{null} ** max_nodes,

        dest: [max_edges]u32 = undefined,
        next: [max_edges]?u32 = undefined,
        prev: [max_edges]?u32 = undefined,

        free: ?u32 = null,
        high: u32 = 0,

        refs: [max_nodes]u32 = [_]u32{0} ** max_nodes,
        work: [max_nodes]u32 = undefined,
        sort: [max_nodes]T = undefined,

        const Self = @This();

        fn alloc(self: *Self) !u32 {
            if (self.free) |e| {
                self.free = self.next[e];
                return e;
            }
            if (self.high >= max_edges) return error.Overflow;
            defer self.high += 1;
            return self.high;
        }

        pub fn add(self: *Self, node: T, dependent: T) !u32 {
            const u: u32 = @intCast(node);
            const v: u32 = @intCast(dependent);
            if (@max(u, v) >= max_nodes) return error.Overflow;
            
            self.n = @max(self.n, @as(u32, @max(u, v)) + 1);
            const e = try self.alloc();
            
            self.dest[e] = v;
            self.next[e] = self.head[u];
            self.prev[e] = null;
            
            if (self.head[u]) |old| self.prev[old] = e;
            self.head[u] = e;
            self.refs[v] += 1;
            
            return e;
        }

        pub fn del(self: *Self, edge: u32, node: T) void {
            const u: u32 = @intCast(node);
            const v = self.dest[edge];
            
            if (self.prev[edge]) |p| {
                self.next[p] = self.next[edge];
            } else {
                self.head[u] = self.next[edge];
            }
            
            if (self.next[edge]) |n| self.prev[n] = self.prev[edge];
            if (self.refs[v] > 0) self.refs[v] -= 1;
            
            self.next[edge] = self.free;
            self.free = edge;
        }

        pub fn resolve(self: *Self) ![]const T {
            @memcpy(self.work[0..self.n], self.refs[0..self.n]);
            
            var tail: u32 = 0;
            for (0..self.n) |i| {
                if (self.work[i] == 0) {
                    self.sort[tail] = @intCast(i);
                    tail += 1;
                }
            }

            var head: u32 = 0;
            while (head < tail) : (head += 1) {
                var it = self.head[@intCast(self.sort[head])];
                while (it) |e| : (it = self.next[e]) {
                    const v = self.dest[e];
                    self.work[v] -= 1;
                    if (self.work[v] == 0) {
                        self.sort[tail] = @intCast(v);
                        tail += 1;
                    }
                }
            }
            
            if (tail != self.n) return error.CycleDetected;
            return self.sort[0..self.n];
        }
    };
}

