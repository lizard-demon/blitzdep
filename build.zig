const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Define the Shared Module
    const blitzdep_mod = b.addModule("blitzdep", .{
        .root_source_file = b.path("src/blitzdep.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 2. Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("blitzdep", blitzdep_mod);

    const run_test = b.addRunArtifact(tests);
    const step = b.step("test", "Run tests and perf benchmarks");
    step.dependOn(&run_test.step);
}
