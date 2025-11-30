const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Define the Shared Module
    const blitzdep_mod = b.addModule("blitzdep", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 2. Correctness Tests
    const correctness_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/correctness.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    correctness_tests.root_module.addImport("blitzdep", blitzdep_mod);

    const run_correctness = b.addRunArtifact(correctness_tests);
    const test_step = b.step("test", "Run correctness tests");
    test_step.dependOn(&run_correctness.step);

    // 3. Performance Tests
    const perf_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    perf_tests.root_module.addImport("blitzdep", blitzdep_mod);

    const run_perf = b.addRunArtifact(perf_tests);
    const perf_step = b.step("perf", "Run performance benchmarks");
    perf_step.dependOn(&run_perf.step);
}
