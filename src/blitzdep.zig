const std = @import("std");

pub fn Graph(comptime T: type, comptime node_max: u32, comptime edge_max: u32) type {
    return struct {
        node_n: u32 = 0,
        edge_n: u32 = 0,
        // Head of linked-lists
        node: [node_max]?u32 = [_]?u32{null} ** node_max,
        // Destination node index
        edge: [edge_max]u32 = undefined,
        // Next edge index in list
        next: [edge_max]?u32 = undefined,

        // Workspace
        dep: [node_max]u32 = undefined,
        sort: [node_max]T = undefined,

        pub fn add(self: *@This(), node: T, deps: anytype) !*@This() {
            const u: u32 = @intCast(node);
            if (u >= node_max or self.edge_n + deps.len > edge_max) return error.Overflow;
            self.node_n = @max(self.node_n, u + 1);

            inline for (deps) |d| {
                const v: u32 = @intCast(d);
                if (v >= node_max) return error.Overflow;
                self.node_n = @max(self.node_n, v + 1);

                self.edge[self.edge_n] = v;
                self.next[self.edge_n] = self.node[u];
                self.node[u] = self.edge_n;
                self.edge_n += 1;
            }
            return self;
        }

        pub fn resolve(self: *@This()) ![]const T {
            @memset(self.dep[0..self.node_n], 0);

            // Calc in-degrees
            for (0..self.node_n) |i| {
                var it = self.node[i];
                while (it) |e| : (it = self.next[e]) self.dep[self.edge[e]] += 1;
            }

            // Seed queue (reusing self.sort)
            var q_head: u32 = 0;
            var q_tail: u32 = 0;

            for (0..self.node_n) |i| {
                if (self.dep[i] == 0) {
                    self.sort[q_tail] = @intCast(i);
                    q_tail += 1;
                }
            }

            // Process
            while (q_head < q_tail) : (q_head += 1) {
                const u = self.sort[q_head];
                var it = self.node[@intCast(u)];
                while (it) |e| : (it = self.next[e]) {
                    const v = self.edge[e];
                    self.dep[v] -= 1;
                    if (self.dep[v] == 0) {
                        self.sort[q_tail] = @intCast(v);
                        q_tail += 1;
                    }
                }
            }

            if (q_tail != self.node_n) return error.CycleDetected;
            return self.sort[0..self.node_n];
        }
    };
}
