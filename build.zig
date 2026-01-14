const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the serial terminal library
    const lib = b.addStaticLibrary(.{
        .name = "serialterm",
        .root_source_file = b.path("src/serial/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add source files
    lib.addCSourceFiles(.{
        .files = &.{},
        .flags = &.{"-std=c11"},
    });

    // Link system libraries for macOS
    if (target.result.os.tag == .macos) {
        lib.linkFramework("IOKit");
        lib.linkFramework("CoreFoundation");
    }

    lib.linkLibC();

    // Install the library
    b.installArtifact(lib);

    // Install headers
    b.installFile("include/serialterm.h", "include/serialterm.h");
    b.installFile("include/transfer.h", "include/transfer.h");

    // Build tests
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/serial/Port.zig"),
        .target = target,
        .optimize = optimize,
    });

    const transfer_tests = b.addTest(.{
        .root_source_file = b.path("src/transfer/xmodem.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const run_transfer_tests = b.addRunArtifact(transfer_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_transfer_tests.step);
}
