# Blitzdep: Lightning-Fast Dependency Resolution

A single-file, zero-dependency Zig library for blazing-fast topological sorting and dependency resolution.

## Why Blitzdep?

- **Ridiculously Fast**: Resolve 1 million dependencies in ~20ms, with O(1) add/delete.
- **Static Realtime Overhead**: Add or remove dependencies in nanoseconds.
- **Compile-Time Ready**: Works at both runtime and compile-time.
- **Zero Dependencies**: Single file, no external dependencies.
- **Type-Safe**: Fully leverages Zig's compile-time guarantees.
- **Memory Efficient**: Fixed compile-time allocation for predictable performance.

Perfect for build systems, package managers, task schedulers, or any system requiring topological ordering.

## Quick Example

```zig
const std = @import("std");
const zdep = @import("blitzdep");

pub fn main() !void {
    // Create a graph: 100 max nodes, 200 max edges
    const Graph = zdep.Graph(u32, 100, 200);
    var g = Graph{};

    // Add dependencies (node -> dependent)
    _ = try g.add(2, 1);        // 2 depends on 1
    _ = try g.add(3, 2);        // 3 depends on 2
    _ = try g.add(4, 1);        // 4 depends on 1
    const e = try g.add(4, 2);  // 4 depends on 2. Save the edge ID.

    // Resolve to topological order
    var sorted = try g.resolve();
    std.debug.print("Build order: {any}\n", .{sorted}); // e.g. [1, 2, 3, 4]

    // Remove a dependency and re-resolve
    g.del(e, 4);
    sorted = try g.resolve();
    std.debug.print("New build order: {any}\n", .{sorted}); // e.g. [1, 3, 2, 4]
}
```

## Performance

The `resolve()` operation is O(N+E). Add/delete operations are O(1).

Benchmarked on a 2017 Chromebook with `ReleaseFast`:

**Resolve Performance**
```
1M nodes, 1K deps each:    21ms  →  91M nodes/s  (10 ns/node)
1M nodes, 10K deps each:   18ms  → 109M nodes/s  ( 9 ns/node)
1M nodes, 50K deps each:   17ms  → 113M nodes/s  ( 8 ns/node)
```
*(See `zig build test` for full performance breakdown of add/delete/sort)*

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

- `T`: Node ID type (typically `u32` or `u16`).
- `node_max`: Maximum number of nodes.
- `edge_max`: Maximum number of edges (dependencies).

### Adding a Dependency

```zig
const edge_id = try g.add(node_id, dependent_id);
```

Adds a single dependency (`node_id` -> `dependent_id`). Returns a unique `edge_id` that can be used later for deletion. Returns `error.Overflow` if capacity is exceeded.

### Deleting a Dependency

```zig
g.del(edge_id, node_id);
```

Removes a dependency using the `edge_id` returned by `add`. The `node_id` (the "from" node) must also be provided. This is an O(1) operation.

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

Run correctness tests and performance benchmarks:

```sh
zig build test -Doptimize=ReleaseFast
```

## How It Works

Blitzdep implements Kahn's algorithm for topological sorting. It uses a custom allocator and an adjacency list representation built on array-backed doubly-linked lists. This allows for O(1) add and delete operations.

- **Adjacency List**: Implemented with fixed arrays and indices, not pointers.
- **Dynamic Edges**: A free list tracks empty edge slots, allowing for efficient reuse.
- **Sorting**: An in-place queue tracks zero-indegree nodes.
- **Memory**: All memory is allocated at compile-time, eliminating runtime allocation overhead.

## License

GPL 3.0
