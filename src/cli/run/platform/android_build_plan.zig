//! Host-managed Android FFI build planning utilities.
//!
//! ## Purpose
//! This module translates a resolved device ABI into normalized Gradle project
//! properties consumed by Android host build scripts. Keeping this logic in a
//! dedicated unit keeps `android_flow.zig` focused on orchestration.
//!
//! ## Compatibility Contract
//! The produced properties are:
//! - `android.injected.build.abi`: narrows Android packaging/build outputs.
//! - `wizig.ffi.abi`: narrows Wizig host-managed Zig FFI build tasks.
//!
//! Unsupported ABI values are rejected early so users get deterministic errors
//! before invoking Gradle.
const std = @import("std");

const android_ffi = @import("android_ffi.zig");

/// Host-side Gradle property plan for Android FFI orchestration.
pub const HostManagedAndroidFfiPlan = struct {
    /// Device/runtime ABI such as `arm64-v8a`.
    abi: []const u8,
    /// Corresponding Zig target triple used by host Gradle FFI tasks.
    zig_target: []const u8,
    /// Gradle property passed to Android plugin ABI filtering.
    injected_build_abi_property: []const u8,
    /// Gradle property passed to Wizig host FFI task selection.
    wizig_ffi_abi_property: []const u8,
};

/// Creates a host-managed Gradle build plan for an Android ABI.
///
/// ## Errors
/// Returns `error.InvalidAndroidAbi` when ABI is not in Wizig's supported map.
pub fn planHostManagedAndroidFfiBuild(
    arena: std.mem.Allocator,
    abi: []const u8,
) !HostManagedAndroidFfiPlan {
    const zig_target = android_ffi.zigTargetForAndroidAbi(abi) orelse return error.InvalidAndroidAbi;
    return .{
        .abi = try arena.dupe(u8, abi),
        .zig_target = try arena.dupe(u8, zig_target),
        .injected_build_abi_property = try std.fmt.allocPrint(arena, "-Pandroid.injected.build.abi={s}", .{abi}),
        .wizig_ffi_abi_property = try std.fmt.allocPrint(arena, "-Pwizig.ffi.abi={s}", .{abi}),
    };
}

test "planHostManagedAndroidFfiBuild maps supported ABI and properties" {
    const plan = try planHostManagedAndroidFfiBuild(std.testing.allocator, "arm64-v8a");
    defer std.testing.allocator.free(plan.abi);
    defer std.testing.allocator.free(plan.zig_target);
    defer std.testing.allocator.free(plan.injected_build_abi_property);
    defer std.testing.allocator.free(plan.wizig_ffi_abi_property);

    try std.testing.expectEqualStrings("arm64-v8a", plan.abi);
    try std.testing.expectEqualStrings("aarch64-linux-android", plan.zig_target);
    try std.testing.expectEqualStrings("-Pandroid.injected.build.abi=arm64-v8a", plan.injected_build_abi_property);
    try std.testing.expectEqualStrings("-Pwizig.ffi.abi=arm64-v8a", plan.wizig_ffi_abi_property);
}

test "planHostManagedAndroidFfiBuild rejects unsupported ABI" {
    try std.testing.expectError(
        error.InvalidAndroidAbi,
        planHostManagedAndroidFfiBuild(std.testing.allocator, "mips64"),
    );
}
