const std = @import("std");

pub fn Graph(comptime T: type, comptime node_max: u32, comptime edge_max: u32) type {
    return struct {
        node_n: u32 = 0,
        edge_n: u32 = 0,
        node: [node_max]?u32 = [_]?u32{null} ** node_max,
        edge: [edge_max]u32 = undefined,
        next: [edge_max]?u32 = undefined,

        dep: [node_max]u32 = undefined,
        sort: [node_max]T = undefined,
        
        pub fn add(self: *@This(), node: T, deps: anytype) !*@This() {
            const node_id: u32 = @intCast(node);
            
            // Check 1: Pre-flight check for Node ID and total Edge capacity
            if (node_id >= node_max or self.edge_n + deps.len > edge_max) return error.Overflow;

            inline for (deps) |t| {
                const dep_id: u32 = @intCast(t);
                
                // Check 2: Check dependency Node ID bounds
                if (dep_id >= node_max) return error.Overflow;

                const max_id = @max(node_id, dep_id);
                // Fix: Force @as(u32, 1) to prevent comptime narrowing to u1
                if (max_id >= self.node_n) self.node_n = max_id + @as(u32, 1);
                
                self.edge[self.edge_n] = dep_id;
                self.next[self.edge_n] = self.node[node_id];
                self.node[node_id] = self.edge_n;
                self.edge_n += 1;
            }
            
            // Fix: Force @as(u32, 1) here as well
            if (node_id >= self.node_n) self.node_n = node_id + @as(u32, 1);
            return self;
        }
        
        pub fn resolve(self: *@This()) error{CycleDetected}![]const T {
            var i: u32 = 0;
            // Reset dependencies
            while (i < self.node_n) : (i += 1) self.dep[i] = 0;
            
            // Calculate in-degrees
            i = 0;
            while (i < self.node_n) : (i += 1) {
                var next_opt = self.node[i];
                while (next_opt) |e| {
                    self.dep[self.edge[e]] += 1;
                    next_opt = self.next[e];
                }
            }
            
            // Initialize queue with 0 in-degree nodes
            var qend: u32 = 0;
            i = 0;
            while (i < self.node_n) : (i += 1) {
                if (self.dep[i] == 0) {
                    self.sort[qend] = @intCast(i);
                    qend += 1;
                }
            }
            
            // Process queue
            var qstart: u32 = 0;
            while (qstart < qend) {
                const nid = self.sort[qstart];
                qstart += 1;
                
                var next_opt = self.node[nid];
                while (next_opt) |e| {
                    const dep_id = self.edge[e];
                    self.dep[dep_id] -= 1;
                    if (self.dep[dep_id] == 0) {
                        self.sort[qend] = @intCast(dep_id);
                        qend += 1;
                    }
                    next_opt = self.next[e];
                }
            }
            
            if (qend != self.node_n) return error.CycleDetected;
            
            return self.sort[0..self.node_n];
        }
    };
}
