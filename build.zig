const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the root module for the serial terminal library
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/serial/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Link system libraries for macOS
    lib_module.linkFramework("IOKit", .{});
    lib_module.linkFramework("CoreFoundation", .{});

    // Build the serial terminal library
    const lib = b.addLibrary(.{
        .name = "serialterm",
        .linkage = .static,
        .root_module = lib_module,
    });

    // Install the library
    b.installArtifact(lib);

    // Install headers
    b.installFile("include/serialterm.h", "include/serialterm.h");
    b.installFile("include/transfer.h", "include/transfer.h");

    // Build tests
    const main_test_module = b.createModule(.{
        .root_source_file = b.path("src/serial/Port.zig"),
        .target = target,
        .optimize = optimize,
    });

    const transfer_test_module = b.createModule(.{
        .root_source_file = b.path("src/transfer/xmodem.zig"),
        .target = target,
        .optimize = optimize,
    });

    const main_tests = b.addTest(.{
        .root_module = main_test_module,
    });

    const transfer_tests = b.addTest(.{
        .root_module = transfer_test_module,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const run_transfer_tests = b.addRunArtifact(transfer_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_transfer_tests.step);
}
