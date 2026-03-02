//! Android ABI resolution helpers for host-managed FFI builds.
//!
//! ## Ownership Model
//! Android FFI compilation is orchestrated by Gradle tasks generated in the
//! app host project. This module is intentionally limited to ABI discovery and
//! normalization so the CLI can select device-compatible build parameters
//! without duplicating library compilation paths.
//!
//! ## Responsibilities
//! - Resolve a connected device ABI via `adb shell getprop`.
//! - Map Android ABIs to Zig target triples.
//! - Provide small parsing helpers covered by unit tests.
const std = @import("std");
const Io = std.Io;

const process = @import("process_supervisor.zig");

/// Resolves device ABI using ordered `getprop` probes.
pub fn resolveAndroidDeviceAbi(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    serial: []const u8,
) ![]const u8 {
    const properties = [_][]const u8{
        "ro.product.cpu.abilist64",
        "ro.product.cpu.abilist",
        "ro.product.cpu.abi",
    };

    for (properties) |property| {
        const result = process.runCapture(arena, io, .{
            .argv = &.{ "adb", "-s", serial, "shell", "getprop", property },
            .label = "resolve Android device ABI",
        }, .{}) catch continue;
        if (!process.termIsSuccess(result.term)) continue;

        if (parseFirstSupportedAndroidAbi(result.stdout)) |abi| {
            return arena.dupe(u8, abi);
        }
    }

    try stderr.print("error: failed to resolve Android ABI for device '{s}'\n", .{serial});
    return error.RunFailed;
}

/// Maps Android ABI to the corresponding Zig target triple.
pub fn zigTargetForAndroidAbi(abi: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, abi, "arm64-v8a")) return "aarch64-linux-android";
    if (std.mem.eql(u8, abi, "armeabi-v7a")) return "arm-linux-androideabi";
    if (std.mem.eql(u8, abi, "x86_64")) return "x86_64-linux-android";
    if (std.mem.eql(u8, abi, "x86")) return "x86-linux-android";
    return null;
}

fn parseFirstSupportedAndroidAbi(raw: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, raw, " \t\r\n,");
    while (it.next()) |token| {
        if (zigTargetForAndroidAbi(token) != null) return token;
    }
    return null;
}

test "zigTargetForAndroidAbi maps supported values" {
    try std.testing.expectEqualStrings("aarch64-linux-android", zigTargetForAndroidAbi("arm64-v8a").?);
    try std.testing.expectEqualStrings("arm-linux-androideabi", zigTargetForAndroidAbi("armeabi-v7a").?);
    try std.testing.expectEqualStrings("x86_64-linux-android", zigTargetForAndroidAbi("x86_64").?);
    try std.testing.expectEqualStrings("x86-linux-android", zigTargetForAndroidAbi("x86").?);
    try std.testing.expect(zigTargetForAndroidAbi("mips64") == null);
}

test "parseFirstSupportedAndroidAbi returns first recognized ABI token" {
    const parsed = parseFirstSupportedAndroidAbi("mips64, x86_64, arm64-v8a").?;
    try std.testing.expectEqualStrings("x86_64", parsed);
}

test "parseFirstSupportedAndroidAbi returns null for unsupported lists" {
    try std.testing.expect(parseFirstSupportedAndroidAbi("mips, mips64, riscv64") == null);
}
