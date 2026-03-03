//! iOS FFI build and bundling support for simulators and real devices.
//!
//! This module builds cached framework binaries and installs
//! `WizigFFI.framework` into app bundle locations expected by runtime loaders.
const std = @import("std");
const Io = std.Io;

const ffi_fingerprint = @import("ffi_fingerprint.zig");
const fs_utils = @import("fs_utils.zig");
const process = @import("process_supervisor.zig");
const workspace_runtime = @import("workspace_runtime.zig");

/// Builds or reuses cached iOS simulator FFI framework binary for the current app.
pub fn buildIosSimulatorFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
    const ffi_inputs = try workspace_runtime.resolveFfiBuildInputs(arena, io, stderr, parent_environ_map, project_root);

    const sdk = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcrun", "--sdk", "iphonesimulator", "--show-sdk-path" },
        .label = "resolve iOS simulator SDK path",
    }, .{});
    const sdk_path = std.mem.trim(u8, sdk.stdout, " \t\r\n");
    if (sdk_path.len == 0) {
        try stderr.writeAll("error: xcrun returned an empty iOS simulator SDK path\n");
        return error.RunFailed;
    }

    const fingerprint = try ffi_fingerprint.computeFfiFingerprint(
        arena,
        io,
        ffi_fingerprint.ios_ffi_cache_version,
        sdk_path,
        ffi_inputs.root_source,
        ffi_inputs.core_source,
        ffi_inputs.app_fingerprint_roots,
    );
    const out_dir = try std.fmt.allocPrint(arena, "/tmp/wizig-ffi-iossim-cache/{s}", .{fingerprint});
    std.Io.Dir.cwd().createDirPath(io, out_dir) catch {};

    const framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ out_dir, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, framework_dir) catch {};

    const out_path = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ framework_dir, std.fs.path.sep_str });
    const info_plist = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ framework_dir, std.fs.path.sep_str });
    if (fs_utils.pathExists(io, out_path)) {
        // Keep cached framework metadata fresh so installer validations do not
        // inherit stale identifiers from old cache versions.
        try writeFrameworkInfoPlist(io, info_plist);
        return out_path;
    }

    const emit_arg = try std.fmt.allocPrint(arena, "-femit-bin={s}", .{out_path});
    const root_arg = try std.fmt.allocPrint(arena, "-Mroot={s}", .{ffi_inputs.root_source});
    const core_arg = try std.fmt.allocPrint(arena, "-Mwizig_core={s}", .{ffi_inputs.core_source});
    const app_arg = if (ffi_inputs.app_source) |app_source| try std.fmt.allocPrint(arena, "-Mwizig_app={s}", .{app_source}) else null;

    var argv = std.ArrayList([]const u8).empty;
    try argv.appendSlice(arena, &.{
        "zig",
        "build-lib",
        "-OReleaseFast",
        "-fno-error-tracing",
        "-fno-unwind-tables",
        "-fstrip",
        "-target",
        "aarch64-ios-simulator",
        "--dep",
        "wizig_core",
    });
    if (app_arg != null) {
        try argv.appendSlice(arena, &.{ "--dep", "wizig_app" });
    }
    try argv.appendSlice(arena, &.{ root_arg, core_arg });
    if (app_arg) |arg| {
        try argv.append(arena, arg);
    }
    try argv.appendSlice(arena, &.{
        "--name",
        "WizigFFI",
        "-dynamic",
        "-install_name",
        "@rpath/WizigFFI.framework/WizigFFI",
        "-headerpad_max_install_names",
        "--sysroot",
        sdk_path,
        "-L/usr/lib",
        "-F/System/Library/Frameworks",
        "-lc",
        emit_arg,
    });

    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = argv.items,
        .label = "build iOS simulator Wizig FFI library",
    }, .{});
    try fixMachoTextPageAlignment(arena, io, stderr, out_path);
    try writeFrameworkInfoPlist(io, info_plist);

    return out_path;
}

/// Builds or reuses cached iOS device FFI framework binary for the current app.
pub fn buildIosDeviceFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
    const ffi_inputs = try workspace_runtime.resolveFfiBuildInputs(arena, io, stderr, parent_environ_map, project_root);

    const sdk = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcrun", "--sdk", "iphoneos", "--show-sdk-path" },
        .label = "resolve iOS device SDK path",
    }, .{});
    const sdk_path = std.mem.trim(u8, sdk.stdout, " \t\r\n");
    if (sdk_path.len == 0) {
        try stderr.writeAll("error: xcrun returned an empty iOS device SDK path\n");
        return error.RunFailed;
    }

    const fingerprint = try ffi_fingerprint.computeFfiFingerprint(
        arena,
        io,
        "wizig-ios-ffi-device-cache-v1",
        sdk_path,
        ffi_inputs.root_source,
        ffi_inputs.core_source,
        ffi_inputs.app_fingerprint_roots,
    );
    const out_dir = try std.fmt.allocPrint(arena, "/tmp/wizig-ffi-iosdev-cache/{s}", .{fingerprint});
    std.Io.Dir.cwd().createDirPath(io, out_dir) catch {};

    const framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ out_dir, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, framework_dir) catch {};

    const out_path = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ framework_dir, std.fs.path.sep_str });
    const info_plist = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ framework_dir, std.fs.path.sep_str });
    if (fs_utils.pathExists(io, out_path)) {
        try writeFrameworkInfoPlist(io, info_plist);
        return out_path;
    }

    const emit_arg = try std.fmt.allocPrint(arena, "-femit-bin={s}", .{out_path});
    const root_arg = try std.fmt.allocPrint(arena, "-Mroot={s}", .{ffi_inputs.root_source});
    const core_arg = try std.fmt.allocPrint(arena, "-Mwizig_core={s}", .{ffi_inputs.core_source});
    const app_arg = if (ffi_inputs.app_source) |app_source| try std.fmt.allocPrint(arena, "-Mwizig_app={s}", .{app_source}) else null;

    var argv = std.ArrayList([]const u8).empty;
    try argv.appendSlice(arena, &.{
        "zig",
        "build-lib",
        "-OReleaseFast",
        "-fno-error-tracing",
        "-fno-unwind-tables",
        "-fstrip",
        "-target",
        "aarch64-ios",
        "--dep",
        "wizig_core",
    });
    if (app_arg != null) {
        try argv.appendSlice(arena, &.{ "--dep", "wizig_app" });
    }
    try argv.appendSlice(arena, &.{ root_arg, core_arg });
    if (app_arg) |arg| {
        try argv.append(arena, arg);
    }
    try argv.appendSlice(arena, &.{
        "--name",
        "WizigFFI",
        "-dynamic",
        "-install_name",
        "@rpath/WizigFFI.framework/WizigFFI",
        "-headerpad_max_install_names",
        "--sysroot",
        sdk_path,
        "-L/usr/lib",
        "-F/System/Library/Frameworks",
        "-lc",
        emit_arg,
    });

    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = argv.items,
        .label = "build iOS device Wizig FFI library",
    }, .{});
    try fixMachoTextPageAlignment(arena, io, stderr, out_path);
    try writeFrameworkInfoPlist(io, info_plist);

    return out_path;
}

/// Copies host framework into device app `Frameworks` location and signs it.
///
/// ## Code Signing
/// Real iOS devices require a valid code signature on all embedded frameworks.
/// When `sign_identity` is provided, the framework and the enclosing app are
/// signed with that identity.  When `null`, ad-hoc signing (`-`) is used as a
/// fallback (suitable for development with automatic provisioning).
pub fn bundleIosFfiLibraryForDevice(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
    sign_identity: ?[]const u8,
) ![]const u8 {
    const frameworks_dir = try std.fmt.allocPrint(arena, "{s}{s}Frameworks", .{ app_path, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, frameworks_dir) catch {};

    const src_framework_dir = std.fs.path.dirname(host_ffi_path) orelse {
        try stderr.writeAll("error: invalid host iOS FFI framework path\n");
        return error.RunFailed;
    };
    const dst_framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ frameworks_dir, std.fs.path.sep_str });
    const frameworks_ffi = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ dst_framework_dir, std.fs.path.sep_str });
    const src_info = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ src_framework_dir, std.fs.path.sep_str });
    const dst_info = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ dst_framework_dir, std.fs.path.sep_str });

    const binary_changed = !try filesEqual(arena, io, host_ffi_path, frameworks_ffi);
    const plist_changed = !try filesEqual(arena, io, src_info, dst_info);
    const changed_frameworks = binary_changed or plist_changed;

    if (changed_frameworks) {
        _ = process.runCapture(arena, io, .{
            .argv = &.{ "rm", "-rf", dst_framework_dir },
            .label = "remove previous iOS device framework staging",
        }, .{}) catch {};
        _ = try process.runCaptureChecked(arena, io, stderr, .{
            .argv = &.{ "cp", "-R", src_framework_dir, dst_framework_dir },
            .label = "copy Wizig framework into iOS device app Frameworks",
        }, .{});
        const identity = sign_identity orelse "-";
        try codesignPathWithIdentity(arena, io, stderr, dst_framework_dir, identity, "codesign staged Wizig framework for iOS device");
        try codesignPathWithIdentity(arena, io, stderr, app_path, identity, "codesign iOS device app after staging Wizig FFI");
    }

    return "@executable_path/Frameworks/WizigFFI.framework/WizigFFI";
}

/// Copies host framework into simulator app `Frameworks` location.
///
/// ## Incrementality
/// Destination files are updated only when bytes differ, preserving filesystem
/// metadata via `cp` while avoiding redundant writes.
///
/// ## Launch Stability
/// On modern simulator runtimes, placing unmanaged dynamic libraries directly in
/// app roots can fail installation preflight. This function stages the runtime
/// as `WizigFFI.framework` and re-signs changed artifacts to satisfy launch
/// policy checks.
pub fn bundleIosFfiLibraryForSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
    const frameworks_dir = try std.fmt.allocPrint(arena, "{s}{s}Frameworks", .{ app_path, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, frameworks_dir) catch {};

    const src_framework_dir = std.fs.path.dirname(host_ffi_path) orelse {
        try stderr.writeAll("error: invalid host iOS FFI framework path\n");
        return error.RunFailed;
    };
    const dst_framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ frameworks_dir, std.fs.path.sep_str });
    const frameworks_ffi = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ dst_framework_dir, std.fs.path.sep_str });
    const src_info = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ src_framework_dir, std.fs.path.sep_str });
    const dst_info = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ dst_framework_dir, std.fs.path.sep_str });

    const binary_changed = !try filesEqual(arena, io, host_ffi_path, frameworks_ffi);
    const plist_changed = !try filesEqual(arena, io, src_info, dst_info);
    const changed_frameworks = binary_changed or plist_changed;

    if (changed_frameworks) {
        _ = process.runCapture(arena, io, .{
            .argv = &.{ "rm", "-rf", dst_framework_dir },
            .label = "remove previous iOS framework staging",
        }, .{}) catch {};
        _ = try process.runCaptureChecked(arena, io, stderr, .{
            .argv = &.{ "cp", "-R", src_framework_dir, dst_framework_dir },
            .label = "copy Wizig framework into iOS app Frameworks",
        }, .{});
        try codesignPath(arena, io, stderr, dst_framework_dir, "codesign staged Wizig framework in iOS Frameworks");
        try codesignPath(arena, io, stderr, app_path, "codesign iOS app after staging Wizig FFI");
    }

    return "@executable_path/Frameworks/WizigFFI.framework/WizigFFI";
}

fn filesEqual(
    arena: std.mem.Allocator,
    io: std.Io,
    src_path: []const u8,
    dst_path: []const u8,
) !bool {
    const src_bytes = try std.Io.Dir.cwd().readFileAlloc(io, src_path, arena, .limited(128 * 1024 * 1024));
    const dst_bytes = std.Io.Dir.cwd().readFileAlloc(io, dst_path, arena, .limited(128 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return std.mem.eql(u8, src_bytes, dst_bytes);
}

fn codesignPath(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    path: []const u8,
    label: []const u8,
) !void {
    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", path },
        .label = label,
    }, .{});
}

fn codesignPathWithIdentity(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    path: []const u8,
    identity: []const u8,
    label: []const u8,
) !void {
    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "/usr/bin/codesign", "--force", "--sign", identity, "--timestamp=none", path },
        .label = label,
    }, .{});
}

/// Fixes Mach-O __TEXT segment page alignment for zig-produced binaries.
///
/// The Zig linker may emit dynamic libraries whose `__TEXT` segment `vmsize`
/// and `filesize` are not rounded up to the 16 KB page boundary required by
/// arm64 iOS devices.  The macOS `codesign` tool and simulator runtimes
/// tolerate this, but real-device AMFI kernel validation rejects the code
/// signature as structurally invalid because page-hash boundaries do not
/// match segment limits.
///
/// This function invokes a small `python3` one-liner that patches the two
/// fields in-place.  It is a no-op when the binary is already aligned or
/// is not a 64-bit Mach-O.
fn fixMachoTextPageAlignment(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    binary_path: []const u8,
) !void {
    const script =
        "import struct,sys\n" ++
        "p=sys.argv[1]\n" ++
        "d=bytearray(open(p,'rb').read())\n" ++
        "if struct.unpack_from('<I',d,0)[0]!=0xFEEDFACF:sys.exit(0)\n" ++
        "o=32\n" ++
        "for _ in range(struct.unpack_from('<I',d,16)[0]):\n" ++
        " c,s=struct.unpack_from('<II',d,o)\n" ++
        " if c==0x19 and d[o+8:o+24].split(b'\\x00')[0]==b'__TEXT':\n" ++
        "  m=0\n" ++
        "  for f in(32,48):\n" ++
        "   v=struct.unpack_from('<Q',d,o+f)[0];a=(v+16383)&~16383\n" ++
        "   if v!=a:struct.pack_into('<Q',d,o+f,a);m=1\n" ++
        "  if m:open(p,'wb').write(d)\n" ++
        "  break\n" ++
        " o+=s\n";
    _ = process.runCapture(arena, io, .{
        .argv = &.{ "python3", "-c", script, binary_path },
        .label = "fix Mach-O __TEXT page alignment for iOS device",
    }, .{}) catch |err| {
        try stderr.print("warning: failed to fix Mach-O page alignment: {s}\n", .{@errorName(err)});
        try stderr.flush();
    };
}

fn writeFrameworkInfoPlist(io: std.Io, out_path: []const u8) !void {
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

/// Resolves existing iOS FFI library path from environment or default output.
pub fn resolveIosFfiLibraryPath(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
    if (parent_environ_map.get("WIZIG_FFI_LIB")) |raw_path| {
        if (std.fs.path.isAbsolute(raw_path)) {
            if (fs_utils.pathExists(io, raw_path)) return try arena.dupe(u8, raw_path);
        } else {
            const cwd = try std.process.currentPathAlloc(io, arena);
            const resolved = try std.fs.path.resolve(arena, &.{ cwd, raw_path });
            if (fs_utils.pathExists(io, resolved)) return resolved;
        }
    }

    const cwd = try std.process.currentPathAlloc(io, arena);
    const framework_guess = try std.fs.path.resolve(arena, &.{ cwd, "zig-out", "lib", "WizigFFI.framework", "WizigFFI" });
    if (fs_utils.pathExists(io, framework_guess)) return framework_guess;
    const guessed = try std.fs.path.resolve(arena, &.{ cwd, "zig-out", "lib", "libwizigffi.dylib" });
    if (fs_utils.pathExists(io, guessed)) return guessed;
    return null;
}
