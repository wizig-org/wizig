//! Shared codegen input resolution and project-spec assembly.
const std = @import("std");
const Io = std.Io;

const api = @import("../model/api.zig");
const compatibility = @import("../compatibility.zig");
const contract_parse = @import("../contract/parse.zig");
const contract_source = @import("../contract/source.zig");
const project_lib_discovery = @import("../project/lib_discovery.zig");
const project_spec = @import("../project/spec.zig");
const project_type_discovery = @import("../project/type_discovery.zig");

/// Fully resolved inputs required by downstream codegen stages.
pub const SpecBundle = struct {
    maybe_source: ?contract_source.ApiContractSource,
    spec: api.ApiSpec,
    compat: compatibility.Metadata,
    app_module_imports: []const []const u8,
};

/// Resolves the contract source, discovered project API, and compatibility metadata.
pub fn build(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) !SpecBundle {
    const maybe_source = try resolveApiSource(api_path, stderr);
    const base_spec = try resolveBaseSpec(arena, io, stderr, project_root, api_path, maybe_source);

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

    return .{
        .maybe_source = maybe_source,
        .spec = spec,
        .compat = try compatibility.buildMetadata(arena, spec),
        .app_module_imports = try project_lib_discovery.collectLibModuleImports(arena, io, project_root),
    };
}

/// Resolves the explicit contract source kind when an API path is present.
fn resolveApiSource(
    api_path: ?[]const u8,
    stderr: *Io.Writer,
) !?contract_source.ApiContractSource {
    if (api_path) |path| {
        return contract_source.apiSourceFromPath(path) catch {
            try stderr.print("error: unsupported API contract extension: {s}\n", .{path});
            try stderr.writeAll("hint: use `.zig` or `.json`\n");
            return error.CodegenFailed;
        };
    }
    return null;
}

/// Loads either the explicit contract or the default discovery-only base spec.
fn resolveBaseSpec(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
    maybe_source: ?contract_source.ApiContractSource,
) !api.ApiSpec {
    if (api_path) |path| {
        const source = maybe_source.?;
        const text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1024 * 1024)) catch |err| {
            try stderr.print("error: failed to read API contract '{s}': {s}\n", .{ path, @errorName(err) });
            return error.CodegenFailed;
        };

        return switch (source) {
            .json => contract_parse.parseApiSpecFromJson(arena, text),
            .zig => contract_parse.parseApiSpecFromZig(arena, text),
        } catch |err| {
            try stderr.print("error: invalid API contract '{s}': {s}\n", .{ path, @errorName(err) });
            return error.CodegenFailed;
        };
    }

    return project_spec.defaultApiSpecForProject(arena, project_root);
}
