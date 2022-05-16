const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const autogen_step = std.build.RunStep.create(b, "cmake");
    autogen_step.addArg("");
    autogen_step.cwd = "./build-notcurses.sh";

    {
        const exe = b.addExecutable("zig-dht", "exe/smiley/main.zig");
        exe.addLibPath("/usr/lib/x86_64-linux-gnu");
        exe.addLibPath("/usr/lib64");
        exe.addPackagePath("dht", "src/index.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.linkLibC();
        exe.defineCMacro("_XOPEN_SOURCE", "1");
        exe.linkSystemLibrary("notcurses");
        exe.linkSystemLibrary("notcurses-core");
        exe.addIncludeDir("/usr/local/include");
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }
    {
        const exe = b.addExecutable("udptest", "exe/udptest/main.zig");
        exe.addLibPath("/usr/lib/x86_64-linux-gnu");
        exe.addLibPath("/usr/lib64");
        exe.addPackagePath("dht", "src/index.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.linkLibC();
        exe.defineCMacro("_XOPEN_SOURCE", "1");
        exe.linkSystemLibrary("notcurses");
        exe.linkSystemLibrary("notcurses-core");
        exe.addIncludeDir("/usr/local/include");
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }

    const nc_step = b.step("notcurses", "Build notcurses");
    nc_step.dependOn(&autogen_step.step);
}
