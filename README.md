# Blitzdep: Lightning-Fast Dependency Resolution

A single-file, zero-dependency Zig library for blazing-fast topological sorting and dependency resolution.

## Why Blitzdep?

- **Ridiculously Fast**: Resolve 1 million dependencies in ~20ms
- **Compile-Time Ready**: Works at both runtime and compile-time
- **Zero Dependencies**: Single file, no external dependencies
- **Type-Safe**: Fully leverages Zig's compile-time guarantees
- **Memory Efficient**: Fixed compile-time allocation for predictable performance

Perfect for build systems, package managers, task schedulers, or any system requiring dependency ordering.

## Quick Example

```zig
const std = @import("std");
const zdep = @import("blitzdep");

pub fn main() !void {
    // Create a graph: 100 max nodes, 200 max edges
    const Graph = zdep.Graph(u32, 100, 200);
    var g = Graph{};

    // Add dependencies (node -> dependencies)
    _ = try g.add(2, .{1});        // 2 depends on 1
    _ = try g.add(3, .{2});        // 3 depends on 2
    _ = try g.add(4, .{1, 2});     // 4 depends on 1 and 2

    // Resolve to topological order
    const sorted = try g.resolve();
    
    // Result: [1, 2, 3, 4] (or valid topological ordering)
    std.debug.print("Build order: {any}\n", .{sorted});
}
```

## Performance

Benchmarked on a 2017 Chromebook with `ReleaseFast`:

```
1M nodes, 1K deps each:    21ms  →  91M nodes/s  (10 ns/node)
1M nodes, 10K deps each:   18ms  → 109M nodes/s  ( 9 ns/node)
1M nodes, 50K deps each:   17ms  → 113M nodes/s  ( 8 ns/node)
```

## Installation

Add to your `build.zig.zon`:

```sh
zig fetch --save "git+https://github.com/lizard-demon/blitzdep#main"
```

In your `build.zig`:

```zig
const blitzdep = b.dependency("blitzdep", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("blitzdep", blitzdep.module("blitzdep"));
```

## API

### Creating a Graph

```zig
const Graph = zdep.Graph(T, node_max, edge_max);
var g = Graph{};
```

- `T`: Node ID type (typically `u32`)
- `node_max`: Maximum number of nodes
- `edge_max`: Maximum number of edges

### Adding Dependencies

```zig
_ = try g.add(node_id, .{ dep1, dep2, ... });
```

Returns `error.Overflow` if capacity exceeded.

### Resolving Order

```zig
const sorted = try g.resolve();
```

Returns a slice of node IDs in topological order, or `error.CycleDetected` if the graph has cycles.

## Compile-Time Usage

```zig
comptime {
    const Graph = zdep.Graph(u32, 10, 20);
    var g = Graph{};
    
    _ = g.add(0, .{1}) catch unreachable;
    _ = g.add(1, .{2}) catch unreachable;
    
    const sorted = g.resolve() catch unreachable;
    // Use sorted at compile-time...
}
```

## Testing

```sh
# Run correctness tests
zig build test

# Run performance benchmarks
zig build perf -Doptimize=ReleaseFast
```

## How It Works

Blitzdep implements Kahn's algorithm for topological sorting with:
- Adjacency list representation using fixed arrays
- In-place queue for zero-indegree nodes
- Single-pass cycle detection
- Cache-friendly memory layout

All memory is allocated at compile-time based on capacity parameters, eliminating runtime allocation overhead.

## License

GPL 3.0
