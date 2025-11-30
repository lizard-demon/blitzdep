# BlitzDep: Absurdly Fast Dependency Analysis

BlitzDep is a single-file, dependency-free Zig module for lightning-fast topological sorting. It's designed for scenarios where performance is critical, such as in build systems, package managers, or any application requiring efficient dependency resolution.

The core of BlitzDep is a compact, highly-optimized Directed Acyclic Graph (DAG) implementation that can resolve dependency order for millions of items in milliseconds at both runtime or compiletime.

## Features

- **Blazing Fast:** Written in optimized Zig for maximum performance. See benchmarks below.
- **Simple API:** A clean and straightforward interface for adding nodes/edges and resolving the graph.
- **Lightweight:** Single-file, no dependencies, easy to integrate into any Zig project.
- **Compile-Time Sized:** Graph capacities are defined at compile-time for optimal memory layout and speed.

## Performance

Benchmarks are run using `zig build perf -Doptimize=ReleaseFast`. The results below demonstrate the ability to sort **1 million nodes** with varying dependency complexities in just a few milliseconds.

_(Performance measured on a 2017 chromebook. Your results may vary.)_

```
// Sorting 1,000,000 nodes with 1,000 dependencies each
Add + Sort  1000000 nodes   1000 links, repeat 5, time:   22ms, 45110220 nodes/s,    22 ns/node.

// Sorting 1,000,000 nodes with 10,000 dependencies each
Add + Sort  1000000 nodes  10000 links, repeat 2, time:   18ms, 55109426 nodes/s,    18 ns/node.

// Sorting 1,000,000 nodes with 500,000 dependencies each
Add + Sort  1000000 nodes 500000 links, repeat 2, time:   17ms, 55824505 nodes/s,    17 ns/node.
```

## Quick Start

1.  **Add as a Dependency:**
    Add BlitzDep to your `build.zig.zon` file. If you have it locally, you can use a path:

    ```zig
    .dependencies = .{
        .blitzdep = .{ .path = "../path/to/blitzdep" },
    },
    ```

2.  **Import in `build.zig`:**
    Fetch the dependency and expose it as a module to your executable or library.

    ```zig
    const blitzdep_dep = b.dependency("blitzdep", .{.target = target, .optimize = optimize});
    const blitzdep_mod = blitzdep_dep.module("blitzdep");
    
    exe.root_module.addImport("blitzdep", blitzdep_mod);
    ```

3.  **Use in Your Code:**
    Import the `Graph` and use it to resolve dependencies. Nodes are represented by integer IDs.

    ```zig
    const std = @import("std");
    const Graph = @import("blitzdep").Graph;

    pub fn main() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        // Define a graph that can hold up to 100 nodes and 200 edges.
        const MyGraph = Graph(u32, 100, 200);
        var g = try allocator.create(MyGraph);
        defer allocator.destroy(g);
        g.* = .{}; // Initialize the graph

        // Add dependencies: node 2 depends on 1, 3 depends on 2.
        _ = g.add(2, . {1});
        _ = g.add(3, .{2});
        _ = g.add(4, .{}); // Node 4 has no dependencies

        // Resolve the dependency order
        const sorted = try g.resolve();

        // The result is a slice of node IDs in topological order.
        // Expected output: something like `[0, 1, 4, 2, 3]` (order of independent nodes may vary)
        std.debug.print("Sorted Order: {any}\n", .{sorted});
    }
    ```

## Building & Testing

This project uses the Zig build system.

-   **Run Correctness Tests:**
    Ensures the graph implementation is correct.
    ```sh
    zig build test
    ```

-   **Run Performance Benchmarks:**
    Measures the speed of the dependency resolution. For best results, use `ReleaseFast` mode.
    ```sh
    zig build perf -Doptimize=ReleaseFast
    ```

