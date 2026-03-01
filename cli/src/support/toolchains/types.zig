//! Shared toolchain policy types.
//!
//! These definitions are consumed by manifest parsing, version probing, doctor
//! diagnostics, and lock-file generation.
const std = @import("std");

/// Stable set of host tools checked by Wizig doctor and captured in lockfiles.
///
/// The ordering of this enum is intentionally treated as policy order across:
/// - doctor output rendering,
/// - lockfile serialization, and
/// - manifest parsing defaults.
pub const ToolId = enum {
    zig,
    xcodebuild,
    xcodegen,
    java,
    gradle,
    adb,
};

/// Number of supported tool ids.
pub const tool_count = @typeInfo(ToolId).@"enum".fields.len;

/// Per-tool policy loaded from `toolchains.toml`.
///
/// `min_version` is evaluated using semantic-ish numeric token comparison and
/// is expected to be non-empty for every known tool.
pub const ToolPolicy = struct {
    id: ToolId,
    required: bool,
    min_version: []const u8,
};

/// Doctor policy section loaded from `toolchains.toml`.
///
/// `strict_default` controls baseline behavior when `wizig doctor` is run
/// without explicit strictness flags.
pub const DoctorPolicy = struct {
    strict_default: bool,
    tools: [tool_count]ToolPolicy,
};

/// Manifest payload used by CLI components.
///
/// `manifest_sha256_hex` is computed from raw `toolchains.toml` bytes so
/// lockfiles can capture the exact policy snapshot used at scaffold time.
pub const ToolchainsManifest = struct {
    schema_version: u32,
    doctor: DoctorPolicy,
    manifest_sha256_hex: []const u8,
};

/// One probed tool version result from host environment.
///
/// `present` distinguishes command availability from parse success. If present
/// is true but parsing fails, `version` is null.
pub const ToolProbe = struct {
    id: ToolId,
    present: bool,
    version: ?[]const u8,
};

/// Human-readable display label for a tool.
///
/// Used for command-line diagnostics where explicit policy keys are not needed.
pub fn toolDisplayName(tool: ToolId) []const u8 {
    return switch (tool) {
        .zig => "zig",
        .xcodebuild => "xcodebuild",
        .xcodegen => "xcodegen",
        .java => "java",
        .gradle => "gradle",
        .adb => "adb",
    };
}

/// Serialization key for lockfile JSON tool maps.
///
/// These values are stable and must match `toolchains.toml` doctor subsection
/// identifiers to keep parser and serializer behavior aligned.
pub fn toolJsonKey(tool: ToolId) []const u8 {
    return switch (tool) {
        .zig => "zig",
        .xcodebuild => "xcodebuild",
        .xcodegen => "xcodegen",
        .java => "java",
        .gradle => "gradle",
        .adb => "adb",
    };
}

/// Returns all known tools in deterministic policy order.
///
/// Callers use this for default construction and index-based matching where
/// compact fixed-size arrays are preferred over hash maps.
pub fn orderedTools() [tool_count]ToolId {
    return .{ .zig, .xcodebuild, .xcodegen, .java, .gradle, .adb };
}
