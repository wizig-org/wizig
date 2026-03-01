//! `wizig doctor` diagnostics for host tools and bundled assets.
//!
//! This command validates host tool presence/version against policy from
//! `toolchains.toml` and supports strict enforcement mode.
const std = @import("std");
const Io = std.Io;

const sdk_locator = @import("../../support/sdk_locator.zig");
const toolchains = @import("../../support/toolchains/root.zig");

/// Parsed `wizig doctor` CLI flags.
///
/// `strict` uses tri-state semantics:
/// - `null`: defer to manifest default,
/// - `true`: force strict mode,
/// - `false`: explicitly disable strict mode.
const DoctorOptions = struct {
    explicit_sdk_root: ?[]const u8 = null,
    strict: ?bool = null,
};

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
    const options = parseDoctorOptions(args, stderr) catch {
        try stderr.flush();
        return error.InvalidArguments;
    };

    try stdout.writeAll("Wizig doctor\n\n");

    const resolved = sdk_locator.resolve(arena, io, env_map, stderr, options.explicit_sdk_root) catch {
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

    const strict_enabled = options.strict orelse manifest.doctor.strict_default;
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
///
/// Keep this in sync with `parseDoctorOptions` whenever flags are added.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Doctor:\n" ++
            "  wizig doctor [--sdk-root <path>] [--strict|--no-strict]\n" ++
            "\n",
    );
}

/// Parses doctor command flags from `args`.
///
/// The parser intentionally rejects unknown options to avoid silent behavior
/// drift in policy enforcement workflows.
fn parseDoctorOptions(args: []const []const u8, stderr: *Io.Writer) !DoctorOptions {
    var options = DoctorOptions{};
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--strict")) {
            options.strict = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-strict")) {
            options.strict = false;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--sdk-root")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --sdk-root\n");
                return error.InvalidArguments;
            }
            options.explicit_sdk_root = args[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--sdk-root=")) {
            options.explicit_sdk_root = arg["--sdk-root=".len..];
            i += 1;
            continue;
        }

        try stderr.print("error: unknown doctor option '{s}'\n", .{arg});
        return error.InvalidArguments;
    }
    return options;
}

test "parseDoctorOptions parses strict and sdk-root" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const parsed = try parseDoctorOptions(
        &.{ "--strict", "--sdk-root", "/tmp/wizig" },
        &err_writer.writer,
    );
    try std.testing.expectEqual(@as(?bool, true), parsed.strict);
    try std.testing.expectEqualStrings("/tmp/wizig", parsed.explicit_sdk_root.?);
}

test "parseDoctorOptions rejects unknown flag" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(
        error.InvalidArguments,
        parseDoctorOptions(&.{"--mystery"}, &err_writer.writer),
    );
}
