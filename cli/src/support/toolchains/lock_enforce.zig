//! Toolchain lock-file enforcement for run/codegen commands.
//!
//! This module validates `.wizig/toolchain.lock.json` (when present) against
//! the current host environment. It intentionally checks policy minima from the
//! lock payload so commands fail fast when host tooling drifts below the locked
//! requirements used at scaffold time.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../fs.zig");
const probe = @import("probe.zig");
const types = @import("types.zig");
const version = @import("version.zig");

const LockToolEntry = struct {
    required: bool,
    min_version: []const u8,
    detected: bool,
    detected_version: ?[]const u8 = null,
};

const LockTools = struct {
    zig: LockToolEntry,
    xcodebuild: LockToolEntry,
    xcodegen: LockToolEntry,
    java: LockToolEntry,
    gradle: LockToolEntry,
    adb: LockToolEntry,
};

const LockPayload = struct {
    schema_version: u32,
    tools: LockTools,
};

/// Enforces project lock policy unless explicitly bypassed.
pub fn enforceProjectLock(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    allow_toolchain_drift: bool,
) !void {
    const lock_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}.wizig{s}toolchain.lock.json",
        .{ project_root, std.fs.path.sep_str, std.fs.path.sep_str },
    );
    if (!fs_util.pathExists(io, lock_path)) return;

    const lock_text = std.Io.Dir.cwd().readFileAlloc(io, lock_path, arena, .limited(1024 * 1024)) catch |err| {
        try stderr.print("error: failed to read toolchain lock '{s}': {s}\n", .{ lock_path, @errorName(err) });
        return error.ToolchainLockReadFailed;
    };

    const parsed = std.json.parseFromSlice(LockPayload, arena, lock_text, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        try stderr.print("error: invalid toolchain lock '{s}': {s}\n", .{ lock_path, @errorName(err) });
        return error.ToolchainLockInvalid;
    };

    if (parsed.value.schema_version != 1) {
        try stderr.print(
            "error: unsupported toolchain lock schema {d} in '{s}'\n",
            .{ parsed.value.schema_version, lock_path },
        );
        return error.ToolchainLockInvalid;
    }

    const policy = policyFromLock(parsed.value.tools);
    const probes = probe.probeAll(arena, io, &policy);

    var violations = std.ArrayList(u8).empty;
    defer violations.deinit(arena);

    for (policy, probes) |tool_policy, tool_probe| {
        if (tool_policy.required and !tool_probe.present) {
            try appendViolation(
                arena,
                &violations,
                "{s}: required by toolchain lock but not detected\n",
                .{types.toolDisplayName(tool_policy.id)},
            );
            continue;
        }

        if (!tool_probe.present) continue;
        if (tool_probe.version) |detected| {
            if (!version.isAtLeast(detected, tool_policy.min_version)) {
                try appendViolation(
                    arena,
                    &violations,
                    "{s}: detected {s} is below locked minimum {s}\n",
                    .{ types.toolDisplayName(tool_policy.id), detected, tool_policy.min_version },
                );
            }
        } else if (tool_policy.required) {
            try appendViolation(
                arena,
                &violations,
                "{s}: detected but version could not be parsed (required by lock)\n",
                .{types.toolDisplayName(tool_policy.id)},
            );
        }
    }

    if (violations.items.len == 0) return;

    if (allow_toolchain_drift) {
        try stderr.print(
            "warning: toolchain drift detected (continuing because --allow-toolchain-drift is set)\n{s}",
            .{violations.items},
        );
        return;
    }

    try stderr.print(
        "error: toolchain drift detected; run `wizig doctor` or use --allow-toolchain-drift to bypass\n{s}",
        .{violations.items},
    );
    return error.ToolchainDrift;
}

fn policyFromLock(lock_tools: LockTools) [types.tool_count]types.ToolPolicy {
    return .{
        .{ .id = .zig, .required = lock_tools.zig.required, .min_version = lock_tools.zig.min_version },
        .{ .id = .xcodebuild, .required = lock_tools.xcodebuild.required, .min_version = lock_tools.xcodebuild.min_version },
        .{ .id = .xcodegen, .required = lock_tools.xcodegen.required, .min_version = lock_tools.xcodegen.min_version },
        .{ .id = .java, .required = lock_tools.java.required, .min_version = lock_tools.java.min_version },
        .{ .id = .gradle, .required = lock_tools.gradle.required, .min_version = lock_tools.gradle.min_version },
        .{ .id = .adb, .required = lock_tools.adb.required, .min_version = lock_tools.adb.min_version },
    };
}

fn appendViolation(
    arena: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const line = try std.fmt.allocPrint(arena, fmt, args);
    defer arena.free(line);
    try out.appendSlice(arena, line);
}

test "policyFromLock preserves lock minima and required flags" {
    const policy = policyFromLock(.{
        .zig = .{ .required = true, .min_version = "0.15.1", .detected = true, .detected_version = "0.16.0" },
        .xcodebuild = .{ .required = true, .min_version = "26.0.0", .detected = true, .detected_version = "26.1" },
        .xcodegen = .{ .required = false, .min_version = "2.39.0", .detected = false, .detected_version = null },
        .java = .{ .required = true, .min_version = "21.0.0", .detected = true, .detected_version = "21.0.3" },
        .gradle = .{ .required = true, .min_version = "9.2.1", .detected = true, .detected_version = "9.2.1" },
        .adb = .{ .required = true, .min_version = "1.0.41", .detected = true, .detected_version = "1.0.41" },
    });

    try std.testing.expectEqual(types.ToolId.zig, policy[0].id);
    try std.testing.expect(policy[0].required);
    try std.testing.expectEqualStrings("0.15.1", policy[0].min_version);
    try std.testing.expect(!policy[2].required);
    try std.testing.expectEqualStrings("2.39.0", policy[2].min_version);
}
