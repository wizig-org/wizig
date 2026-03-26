//! Low-level iOS FFI framework helpers.
//!
//! The build and bundle modules share these helpers for Mach-O page alignment,
//! byte-for-byte equality checks, and framework Info.plist generation.
const std = @import("std");

const fs_utils = @import("../fs_utils.zig");

/// Fixes Mach-O `__TEXT` segment page alignment for iOS arm64 AMFI validation.
pub fn fixMachoTextPageAlignment(io: std.Io, path: []const u8) !void {
    const page_mask: u64 = 16383;

    var file = std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_write }) catch return;
    defer file.close(io);

    const file_len = (file.stat(io) catch return).size;
    if (file_len < 32) return;

    // Read the Mach-O header (first 20 bytes) via positional read.
    var header_buf: [20]u8 = undefined;
    _ = file.readPositional(io, &.{&header_buf}, 0) catch return;

    if (std.mem.readInt(u32, header_buf[0..4], .little) != 0xFEEDFACF) return;
    const ncmds = std.mem.readInt(u32, header_buf[16..20], .little);

    var offset: u64 = 32;
    for (0..ncmds) |_| {
        if (offset + 72 > file_len) return;
        var cmd_buf: [72]u8 = undefined;
        _ = file.readPositional(io, &.{&cmd_buf}, offset) catch return;

        const cmd = std.mem.readInt(u32, cmd_buf[0..4], .little);
        const cmdsize = std.mem.readInt(u32, cmd_buf[4..8], .little);
        if (cmdsize == 0) return;

        // LC_SEGMENT_64 = 0x19, segname at +8.
        if (cmd == 0x19 and std.mem.eql(u8, cmd_buf[8..14], "__TEXT") and cmd_buf[14] == 0) {
            // vmsize at segment+32, filesize at segment+48.
            inline for (.{ 32, 48 }) |field_off| {
                const val = std.mem.readInt(u64, cmd_buf[field_off..][0..8], .little);
                const aligned = (val + page_mask) & ~page_mask;
                if (val != aligned) {
                    var write_buf: [8]u8 = undefined;
                    std.mem.writeInt(u64, &write_buf, aligned, .little);
                    file.writePositionalAll(io, &write_buf, offset + field_off) catch return;
                }
            }
            return;
        }

        offset += cmdsize;
    }
}

/// Returns `true` when both files exist and contain identical bytes.
pub fn filesEqual(
    arena: std.mem.Allocator,
    io: std.Io,
    src_path: []const u8,
    dst_path: []const u8,
) !bool {
    _ = arena;

    var src = try std.Io.Dir.cwd().openFile(io, src_path, .{});
    defer src.close(io);
    var dst = std.Io.Dir.cwd().openFile(io, dst_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer dst.close(io);

    const src_size = (try src.stat(io)).size;
    const dst_size = (try dst.stat(io)).size;
    if (src_size != dst_size) return false;

    var src_buf: [64 * 1024]u8 = undefined;
    var dst_buf: [64 * 1024]u8 = undefined;
    var offset: u64 = 0;
    while (offset < src_size) {
        const to_read: usize = @intCast(@min(src_size - offset, src_buf.len));
        const src_len = try src.readPositional(io, &.{src_buf[0..to_read]}, offset);
        const dst_len = try dst.readPositional(io, &.{dst_buf[0..to_read]}, offset);
        if (src_len != dst_len) return false;
        if (!std.mem.eql(u8, src_buf[0..src_len], dst_buf[0..dst_len])) return false;
        offset += src_len;
    }

    return true;
}

/// Writes the framework `Info.plist` used by iOS bundle validators.
pub fn writeFrameworkInfoPlist(io: std.Io, out_path: []const u8) !void {
    const contents =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" ++
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" ++
        "<plist version=\"1.0\">\n" ++
        "<dict>\n" ++
        "    <key>CFBundleDevelopmentRegion</key>\n" ++
        "    <string>en</string>\n" ++
        "    <key>CFBundleExecutable</key>\n" ++
        "    <string>WizigFFI</string>\n" ++
        "    <key>CFBundleIdentifier</key>\n" ++
        "    <string>dev.wizig.WizigFFI.framework</string>\n" ++
        "    <key>CFBundleInfoDictionaryVersion</key>\n" ++
        "    <string>6.0</string>\n" ++
        "    <key>CFBundleName</key>\n" ++
        "    <string>WizigFFI</string>\n" ++
        "    <key>CFBundlePackageType</key>\n" ++
        "    <string>FMWK</string>\n" ++
        "    <key>CFBundleShortVersionString</key>\n" ++
        "    <string>1.0</string>\n" ++
        "    <key>CFBundleVersion</key>\n" ++
        "    <string>1</string>\n" ++
        "</dict>\n" ++
        "</plist>\n";
    try fs_utils.writeFileAtomically(io, out_path, contents);
}
