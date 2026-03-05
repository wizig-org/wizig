//! `wizig codegen` command orchestration and public wrappers.
const std = @import("std");
const Io = std.Io;
const fs_util = @import("../../support/fs.zig");
const path_util = @import("../../support/path.zig");
const lock_enforce = @import("../../support/toolchains/lock_enforce.zig");
const android_gradle_migration = @import("../../run/platform/android_gradle_migration.zig");
const compatibility = @import("compatibility.zig");
const ios_host_patch = @import("ios_host_patch.zig");
const options = @import("options.zig");
const targets = @import("targets.zig");
const watch_runner = @import("watch/runner.zig");
const contract_source = @import("contract/source.zig");
const contract_resolve = @import("contract/resolve.zig");
const contract_parse = @import("contract/parse.zig");
const project_ios_c_artifacts = @import("project/ios_c_artifacts.zig");
const project_ios_sdk_ffi_mirror = @import("project/ios_sdk_ffi_mirror.zig");
const project_spec = @import("project/spec.zig");
const project_lib_discovery = @import("project/lib_discovery.zig");
const project_type_discovery = @import("project/type_discovery.zig");
const project_paths = @import("project/paths.zig");
const render_zig_api = @import("render/zig_api.zig");
const render_zig_ffi_root = @import("render/zig_ffi_root.zig");
const render_zig_app_module = @import("render/zig_app_module.zig");
const render_swift_api = @import("render/swift_api.zig");
const render_kotlin_api = @import("render/kotlin_api.zig");
const render_android_jni_bridge = @import("render/android_jni_bridge.zig");
const render_android_jni_cmake = @import("render/android_jni_cmake.zig");
pub const ApiContractSource = contract_source.ApiContractSource;
pub const ResolvedApiContract = contract_source.ResolvedApiContract;
/// Parses codegen CLI options and triggers project generation.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed = try options.parseCodegenOptions(args, stderr);
    const root_abs = try path_util.resolveAbsolute(arena, io, parsed.project_root);

    try lock_enforce.enforceProjectLock(
        arena,
        io,
        stderr,
        root_abs,
        parsed.allow_toolchain_drift,
    );

    if (parsed.watch) {
        try watch_runner.runWatchCodegenLoop(
            io,
            stderr,
            stdout,
            root_abs,
            parsed.api_override,
            parsed.watch_interval_ms,
            resolveApiPathForWatch,
            generateProject,
        );
        return;
    }

    const contract = try resolveApiContract(arena, io, stderr, root_abs, parsed.api_override);
    try generateProject(
        arena,
        io,
        stderr,
        stdout,
        root_abs,
        if (contract) |resolved| resolved.path else null,
    );
}

/// Writes usage help for the codegen command.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    const ts_supported = targets.supportedNow(.typescript);
    try writer.writeAll(
        "Codegen:\n" ++
            "  wizig codegen [project_root] [--api <path>] [--watch] [--watch-interval-ms <milliseconds>] [--allow-toolchain-drift]\n" ++
            "  # default contract lookup: wizig.api.zig -> wizig.api.json (optional)\n" ++
            "  # watch mode: incremental codegen on lib/**/*.zig and contract changes\n" ++
            "  # current targets: zig, swift, kotlin\n",
    );
    try writer.print("  # default watch interval: {d}ms\n", .{options.default_watch_interval_ms});
    try writer.print("  # reserved target: typescript ({s})\n\n", .{if (ts_supported) "enabled" else "planned"});
}

/// Resolves API contract path from explicit override or project defaults.
pub fn resolveApiContract(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) !?ResolvedApiContract {
    return contract_resolve.resolveApiContract(arena, io, stderr, project_root, api_override);
}

/// Generates Zig/Swift/Kotlin API bindings from contract + `lib/**/*.zig` discovery.
pub fn generateProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) !void {
    const maybe_source: ?ApiContractSource = if (api_path) |path| blk: {
        const source = contract_source.apiSourceFromPath(path) catch {
            try stderr.print("error: unsupported API contract extension: {s}\n", .{path});
            try stderr.writeAll("hint: use `.zig` or `.json`\n");
            return error.CodegenFailed;
        };
        break :blk source;
    } else null;

    const base_spec = if (api_path) |path| blk: {
        const source = maybe_source.?;
        const text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1024 * 1024)) catch |err| {
            try stderr.print("error: failed to read API contract '{s}': {s}\n", .{ path, @errorName(err) });
            return error.CodegenFailed;
        };

        break :blk switch (source) {
            .json => contract_parse.parseApiSpecFromJson(arena, text),
            .zig => contract_parse.parseApiSpecFromZig(arena, text),
        } catch |err| {
            try stderr.print("error: invalid API contract '{s}': {s}\n", .{ path, @errorName(err) });
            return error.CodegenFailed;
        };
    } else try project_spec.defaultApiSpecForProject(arena, project_root);

    const discovered_types = try project_type_discovery.discoverLibTypes(arena, io, project_root);
    const discovered_methods = try project_lib_discovery.discoverLibApiMethodsWithTypes(
        arena,
        io,
        project_root,
        discovered_types.struct_names,
        discovered_types.enum_names,
    );
    const spec = try project_spec.mergeSpecWithDiscoveredTypes(
        arena,
        base_spec,
        discovered_methods,
        discovered_types.structs,
        discovered_types.enums,
    );
    const compat = try compatibility.buildMetadata(arena, spec);

    const generated_root = try path_util.join(arena, project_root, ".wizig/generated");
    const zig_dir = try path_util.join(arena, generated_root, "zig");
    const swift_dir = try path_util.join(arena, generated_root, "swift");
    const kotlin_dir = try path_util.join(arena, generated_root, "kotlin/dev/wizig");
    const android_jni_dir = try path_util.join(arena, generated_root, "android/jni");
    const app_module_imports = try project_lib_discovery.collectLibModuleImports(arena, io, project_root);

    try fs_util.ensureDir(io, zig_dir);
    try fs_util.ensureDir(io, swift_dir);
    try fs_util.ensureDir(io, kotlin_dir);
    try fs_util.ensureDir(io, android_jni_dir);

    const zig_out = try render_zig_api.renderZigApi(arena, spec);
    const zig_ffi_root_out = try render_zig_ffi_root.renderZigFfiRoot(arena, spec, compat);
    const zig_app_module_out = try render_zig_app_module.renderZigAppModule(arena, spec, app_module_imports);
    const swift_out = try render_swift_api.renderSwiftApi(arena, spec, compat);
    const kotlin_out = try render_kotlin_api.renderKotlinApi(arena, spec, compat);
    const android_jni_bridge_out = try render_android_jni_bridge.renderAndroidJniBridge(arena, spec, compat);
    const android_jni_cmake_out = try render_android_jni_cmake.renderAndroidJniCmake(arena);
    const ios_c_artifacts = try project_ios_c_artifacts.generate(arena, io, stderr, project_root, generated_root, spec);

    const zig_file = try path_util.join(arena, zig_dir, "WizigGeneratedApi.zig");
    const zig_ffi_root_file = try path_util.join(arena, zig_dir, "WizigGeneratedFfiRoot.zig");
    const zig_app_module_file = try path_util.join(arena, project_root, "lib/WizigGeneratedAppModule.zig");
    const swift_file = try path_util.join(arena, swift_dir, "WizigGeneratedApi.swift");
    const kotlin_file = try path_util.join(arena, kotlin_dir, "WizigGeneratedApi.kt");
    const android_jni_bridge_file = try path_util.join(arena, android_jni_dir, "WizigGeneratedApiBridge.c");
    const android_jni_cmake_file = try path_util.join(arena, android_jni_dir, "CMakeLists.txt");
    const ios_mirror_swift_file = try project_paths.resolveIosMirrorSwiftFile(arena, io, project_root);
    const sdk_swift_file = try project_paths.resolveSdkSwiftApiFile(arena, io, project_root);
    const sdk_ios_runtime_file = try project_paths.resolveSdkIosRuntimeFile(arena, io, project_root);
    const sdk_kotlin_file = try project_paths.resolveSdkKotlinApiFile(arena, io, project_root);

    const zig_changed = try fs_util.writeFileIfChanged(arena, io, zig_file, zig_out);
    const zig_ffi_changed = try fs_util.writeFileIfChanged(arena, io, zig_ffi_root_file, zig_ffi_root_out);
    const zig_app_module_changed = try fs_util.writeFileIfChanged(arena, io, zig_app_module_file, zig_app_module_out);
    const swift_changed = try fs_util.writeFileIfChanged(arena, io, swift_file, swift_out);
    const kotlin_changed = try fs_util.writeFileIfChanged(arena, io, kotlin_file, kotlin_out);
    const android_jni_bridge_changed = try fs_util.writeFileIfChanged(arena, io, android_jni_bridge_file, android_jni_bridge_out);
    const android_jni_cmake_changed = try fs_util.writeFileIfChanged(arena, io, android_jni_cmake_file, android_jni_cmake_out);

    const ios_mirror_changed = if (ios_mirror_swift_file) |mirror_path|
        try fs_util.writeFileIfChanged(arena, io, mirror_path, swift_out)
    else
        false;
    const sdk_swift_changed = if (sdk_swift_file) |sdk_path|
        try fs_util.writeFileIfChanged(arena, io, sdk_path, swift_out)
    else
        false;

    var sdk_ios_runtime_changed = false;
    if (sdk_ios_runtime_file) |sdk_path| {
        if (try project_paths.resolveBundledIosRuntimeSource(arena, io)) |source_path| {
            const runtime_source = std.Io.Dir.cwd().readFileAlloc(io, source_path, arena, .limited(1024 * 1024)) catch |err| blk: {
                try stderr.print("warning: failed to read iOS runtime source '{s}': {s}\n", .{ source_path, @errorName(err) });
                break :blk null;
            };
            if (runtime_source) |content| {
                sdk_ios_runtime_changed = try fs_util.writeFileIfChanged(arena, io, sdk_path, content);
            }
        }
    }

    const sdk_kotlin_changed = if (sdk_kotlin_file) |sdk_path|
        try fs_util.writeFileIfChanged(arena, io, sdk_path, kotlin_out)
    else
        false;

    try project_ios_sdk_ffi_mirror.mirrorGeneratedIosFfiArtifacts(arena, io, project_root, spec);

    const ios_host_patch_summary = ios_host_patch.ensureIosHostBuildPhase(arena, io, project_root) catch |err| blk: {
        try stderr.print("warning: failed to patch iOS host project for Wizig FFI build phase: {s}\n", .{@errorName(err)});
        break :blk ios_host_patch.PatchSummary{};
    };

    const android_project_root = try path_util.join(arena, project_root, "android");
    const android_host_patch_summary = if (fs_util.pathExists(io, android_project_root))
        android_gradle_migration.ensureBuildGradleKtsCompatibility(
            arena,
            io,
            android_project_root,
            "app",
        ) catch |err| blk: {
            try stderr.print("warning: failed to patch Android host Gradle for Wizig FFI build tasks: {s}\n", .{@errorName(err)});
            break :blk android_gradle_migration.MigrationSummary{};
        }
    else
        android_gradle_migration.MigrationSummary{};

    if (zig_changed or zig_ffi_changed or zig_app_module_changed or swift_changed or kotlin_changed or android_jni_bridge_changed or android_jni_cmake_changed or ios_c_artifacts.changed or ios_mirror_changed or sdk_swift_changed or sdk_ios_runtime_changed or sdk_kotlin_changed) {
        try stdout.print("generated API bindings ({s})\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}", .{
            if (maybe_source) |source| if (source == .zig) "zig contract + discovery" else "json contract + discovery" else "auto-discovery",
            zig_file,
            zig_ffi_root_file,
            zig_app_module_file,
            swift_file,
            kotlin_file,
            android_jni_bridge_file,
            android_jni_cmake_file,
        });
        try stdout.print("\n- {s}\n- {s}\n- {s}\n- {s}", .{
            ios_c_artifacts.paths.generated_api_header,
            ios_c_artifacts.paths.framework_header,
            ios_c_artifacts.paths.modulemap,
            ios_c_artifacts.paths.canonical_header,
        });
        if (ios_mirror_swift_file) |mirror_path| {
            try stdout.print("\n- {s}", .{mirror_path});
        }
        if (sdk_swift_file) |sdk_path| {
            try stdout.print("\n- {s}", .{sdk_path});
        }
        if (sdk_ios_runtime_file) |sdk_path| {
            try stdout.print("\n- {s}", .{sdk_path});
        }
        if (sdk_kotlin_file) |sdk_path| {
            try stdout.print("\n- {s}", .{sdk_path});
        }
        try stdout.writeAll("\n");
    } else {
        try stdout.print("API bindings unchanged ({s})\n", .{
            if (maybe_source) |source| if (source == .zig) "zig contract + discovery" else "json contract + discovery" else "auto-discovery",
        });
    }

    if (ios_host_patch_summary.patched_projects > 0) {
        try stdout.print(
            "updated iOS host FFI build phase in {d}/{d} project(s)\n",
            .{ ios_host_patch_summary.patched_projects, ios_host_patch_summary.scanned_projects },
        );
    }
    if (android_host_patch_summary.patched) {
        try stdout.writeAll("updated Android host Gradle FFI task compatibility in app/build.gradle.kts\n");
    }
    try stdout.flush();
}

fn resolveApiPathForWatch(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) !?[]const u8 {
    const contract = try resolveApiContract(arena, io, stderr, project_root, api_override);
    return if (contract) |resolved| resolved.path else null;
}
test {
    _ = @import("render/tests.zig");
}
