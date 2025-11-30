const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Get the dependency defined in build.zig.zon
    const blitzdep_dep = b.dependency("blitzdep", .{
        .target = target,
        .optimize = optimize,
    });
    
    // 2. Extract the module exposed by the library
    const blitzdep_mod = blitzdep_dep.module("blitzdep");

    // 3. Build the Package Manager executable
    const exe = b.addExecutable(.{
        .name = "bpm",
        // We create the root module explicitly to add imports
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // 4. Import the module into our executable
    exe.root_module.addImport("blitzdep", blitzdep_mod);

    // 5. Standard install & run steps
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Blitz Package Manager");
    run_step.dependOn(&run_cmd.step);
}
