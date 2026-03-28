//! `wizig doctor` diagnostics for host tools and bundled assets.
//!
//! This command validates host tool presence/version against policy from
//! `toolchains.toml` and supports strict enforcement mode.
const std = @import("std");
const Io = std.Io;

const options = @import("options.zig");
const sdk_locator = @import("../../support/sdk_locator.zig");
const toolchains = @import("../../support/toolchains/root.zig");

/// Runs environment diagnostics and toolchain policy checks.
///
/// The command validates SDK bundle presence, then checks host tools against
/// `toolchains.toml` policy and reports warning/failure based on strict mode.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed = try options.parseDoctorOptions(arena, stderr, args);
    if (parsed == null) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }
    const doctor_options = parsed.?;

    try stdout.writeAll("Wizig doctor\n\n");

    const resolved = sdk_locator.resolve(arena, io, env_map, stderr, doctor_options.explicit_sdk_root) catch {
        try stdout.writeAll("[missing] Wizig SDK bundle\n");
        try stdout.flush();
        return error.DoctorFailed;
    };
    try stdout.print("[ok] sdk_root: {s}\n", .{resolved.root});
    try stdout.print("[ok] templates: {s}\n", .{resolved.templates_dir});
    try stdout.print("[ok] runtime: {s}\n\n", .{resolved.runtime_dir});

    const manifest = toolchains.manifest.loadFromRoot(arena, io, stderr, resolved.root) catch {
        try stdout.writeAll("[missing] toolchains.toml\n");
        try stdout.flush();
        return error.DoctorFailed;
    };

    const strict_enabled = doctor_options.strict orelse manifest.doctor.strict_default;
    const probes = toolchains.probe.probeAll(arena, io, &manifest.doctor.tools);

    var required_issues: usize = 0;
    var optional_issues: usize = 0;

    for (manifest.doctor.tools, probes) |policy, probed| {
        const label = toolchains.types.toolDisplayName(policy.id);

        if (!probed.present) {
            if (policy.required) {
                required_issues += 1;
                try stdout.print("[warn] {s}: missing (required, min {s})\n", .{ label, policy.min_version });
            } else {
                optional_issues += 1;
                try stdout.print("[warn] {s}: missing (optional, min {s})\n", .{ label, policy.min_version });
            }
            continue;
        }

        const version = probed.version orelse {
            if (policy.required) {
                required_issues += 1;
            } else {
                optional_issues += 1;
            }
            try stdout.print("[warn] {s}: detected but version could not be parsed\n", .{label});
            continue;
        };

        const meets_min = toolchains.version.isAtLeast(version, policy.min_version);
        if (meets_min) {
            try stdout.print("[ok] {s}: {s} (min {s})\n", .{ label, version, policy.min_version });
        } else {
            if (policy.required) {
                required_issues += 1;
            } else {
                optional_issues += 1;
            }
            try stdout.print("[warn] {s}: {s} < {s}\n", .{ label, version, policy.min_version });
        }
    }

    const total_issues = required_issues + optional_issues;
    if (total_issues == 0) {
        try stdout.writeAll("\nResult: healthy\n");
        try stdout.flush();
        return;
    }

    if (strict_enabled) {
        try stdout.print(
            "\nResult: failed (strict mode, {d} required issue(s), {d} optional issue(s))\n",
            .{ required_issues, optional_issues },
        );
        try stdout.flush();
        return error.DoctorFailed;
    }

    try stdout.print(
        "\nResult: warnings ({d} required issue(s), {d} optional issue(s); rerun with --strict to enforce)\n",
        .{ required_issues, optional_issues },
    );
    try stdout.flush();
}

/// Writes usage help for the doctor command.
pub fn printUsage(writer: *Io.Writer) !void {
    try options.printUsage(writer);
}

test "printUsage includes doctor syntax" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    const output = out_writer.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--strict") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--no-strict") != null);
}
