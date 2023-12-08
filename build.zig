const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const network = b.dependency("network", .{});
    const libre_ssl_dep = b.dependency("libressl", .{ .target = target, .optimize = optimize });

    const libtls = libre_ssl_dep.artifact("tls");
    if (optimize == .ReleaseSmall) {
        libtls.want_lto = true;
        libtls.strip = true;
    }

    const server = b.addExecutable(.{
        .name = "zgem_server",
        .root_source_file = .{ .path = "src/server.zig" },
        .target = target,
        .optimize = optimize,
    });
    server.linkLibC();

    server.addModule("network", network.module("network"));
    server.linkLibrary(libtls);

    if (optimize == .ReleaseSmall) {
        server.strip = true;
        server.want_lto = true;
    }

    b.installArtifact(server);

    const client = b.addExecutable(.{
        .name = "zgem",
        .root_source_file = .{ .path = "src/client.zig" },
        .target = target,
        .optimize = optimize,
    });
    // client.linkLibC();

    client.addModule("network", network.module("network"));

    if (optimize == .ReleaseSmall) {
        client.strip = true;
        client.want_lto = true;
    }

    b.installArtifact(client);

    const run_server_cmd = b.addRunArtifact(server);
    run_server_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_server_cmd.addArgs(args);
    }
    const run_server_step = b.step("server", "Run the app");
    run_server_step.dependOn(&run_server_cmd.step);

    const run_client_cmd = b.addRunArtifact(client);
    run_client_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_client_cmd.addArgs(args);
    }
    const run_client_step = b.step("client", "Run the app");
    run_client_step.dependOn(&run_client_cmd.step);
}
