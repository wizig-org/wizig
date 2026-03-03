//! Discovery of API method signatures and module imports from `lib/**/*.zig`.

const std = @import("std");
const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const api = @import("../model/api.zig");

pub fn discoverLibApiMethods(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const api.ApiMethod {
    const lib_dir = try path_util.join(arena, project_root, "lib");
    if (!fs_util.pathExists(io, lib_dir)) return &.{};

    var lib = std.Io.Dir.cwd().openDir(io, lib_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer lib.close(io);

    var walker = try lib.walk(arena);
    defer walker.deinit();

    var rel_paths = std.ArrayList([]const u8).empty;
    errdefer rel_paths.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        if (std.mem.eql(u8, entry.path, "WizigGeneratedAppModule.zig")) continue;

        const rel = try arena.dupe(u8, entry.path);
        for (rel) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        try rel_paths.append(arena, rel);
    }

    std.mem.sort([]const u8, rel_paths.items, {}, lessString);

    var discovered = std.ArrayList(api.ApiMethod).empty;
    errdefer discovered.deinit(arena);

    for (rel_paths.items) |rel_path| {
        const abs_path = try path_util.join(arena, lib_dir, rel_path);
        const source = std.Io.Dir.cwd().readFileAlloc(io, abs_path, arena, .limited(2 * 1024 * 1024)) catch continue;
        const methods = try parseApiMethodsFromLibSource(arena, source);
        for (methods) |method| {
            var exists = false;
            for (discovered.items) |existing| {
                if (std.mem.eql(u8, existing.name, method.name)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) try discovered.append(arena, method);
        }
    }

    return discovered.toOwnedSlice(arena);
}

pub fn collectLibModuleImports(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
    const lib_dir = try path_util.join(arena, project_root, "lib");
    if (!fs_util.pathExists(io, lib_dir)) return &.{};

    var lib = std.Io.Dir.cwd().openDir(io, lib_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer lib.close(io);

    var walker = try lib.walk(arena);
    defer walker.deinit();

    var imports = std.ArrayList([]const u8).empty;
    errdefer imports.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;

        const rel = try arena.dupe(u8, entry.path);
        for (rel) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        if (std.mem.eql(u8, rel, "WizigGeneratedAppModule.zig")) continue;
        const import_path = try arena.dupe(u8, rel);
        try imports.append(arena, import_path);
    }

    std.mem.sort([]const u8, imports.items, {}, lessString);
    return imports.toOwnedSlice(arena);
}

fn parseApiMethodsFromLibSource(arena: std.mem.Allocator, source: []const u8) ![]const api.ApiMethod {
    var methods = std.ArrayList(api.ApiMethod).empty;
    errdefer methods.deinit(arena);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "pub fn ")) |start| {
        cursor = start + "pub fn ".len;
        while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}

        const name_start = cursor;
        if (name_start >= source.len or !isIdentStart(source[name_start])) continue;
        cursor += 1;
        while (cursor < source.len and isIdentContinue(source[cursor])) : (cursor += 1) {}
        const name = source[name_start..cursor];

        while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}
        if (cursor >= source.len or source[cursor] != '(') continue;

        const params_start = cursor + 1;
        cursor += 1;
        var depth: usize = 1;
        while (cursor < source.len and depth > 0) : (cursor += 1) {
            switch (source[cursor]) {
                '(' => depth += 1,
                ')' => depth -= 1,
                else => {},
            }
        }
        if (depth != 0 or cursor == 0) break;
        const params_end = cursor - 1;

        while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}
        const return_start = cursor;
        while (cursor < source.len and source[cursor] != '{' and source[cursor] != ';') : (cursor += 1) {}
        if (cursor <= return_start) continue;
        const return_raw = std.mem.trim(u8, source[return_start..cursor], " \t\r\n");

        if (try methodFromLibSignature(arena, name, source[params_start..params_end], return_raw)) |method| {
            try methods.append(arena, method);
        }
    }

    return methods.toOwnedSlice(arena);
}

fn methodFromLibSignature(
    arena: std.mem.Allocator,
    name: []const u8,
    params_raw: []const u8,
    return_raw: []const u8,
) !?api.ApiMethod {
    if (return_raw.len == 0) return null;

    var param_types = std.ArrayList([]const u8).empty;
    errdefer param_types.deinit(arena);

    var parts = std.mem.splitScalar(u8, params_raw, ',');
    while (parts.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t\r\n");
        if (part.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, part, ':') orelse return null;
        var ty = std.mem.trim(u8, part[colon + 1 ..], " \t\r\n");
        if (std.mem.indexOfScalar(u8, ty, '=')) |eq| {
            ty = std.mem.trim(u8, ty[0..eq], " \t\r\n");
        }
        try param_types.append(arena, try normalizeTypeToken(arena, ty));
    }

    var allocator_param = false;
    var input_type: api.ApiType = .void;
    switch (param_types.items.len) {
        0 => {},
        1 => {
            if (isAllocatorType(param_types.items[0])) {
                allocator_param = true;
            } else {
                input_type = parseLibParamType(param_types.items[0]) orelse return null;
            }
        },
        2 => {
            input_type = parseLibParamType(param_types.items[0]) orelse return null;
            if (!isAllocatorType(param_types.items[1])) return null;
            allocator_param = true;
        },
        else => return null,
    }

    var ret = std.mem.trim(u8, return_raw, " \t\r\n");
    if (ret.len == 0) return null;
    if (ret[0] == '!') ret = std.mem.trim(u8, ret[1..], " \t\r\n");
    const ret_norm = try normalizeTypeToken(arena, ret);
    const output_type = parseLibReturnType(ret_norm) orelse return null;

    if (output_type == .string and !allocator_param) return null;
    if (output_type != .string and allocator_param) return null;

    return .{
        .name = try arena.dupe(u8, name),
        .input = input_type,
        .output = output_type,
    };
}

fn normalizeTypeToken(arena: std.mem.Allocator, raw: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);
    for (raw) |ch| {
        if (std.ascii.isWhitespace(ch)) continue;
        try out.append(arena, ch);
    }
    return out.toOwnedSlice(arena);
}

fn isAllocatorType(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "std.mem.Allocator");
}

fn parseLibParamType(ty: []const u8) ?api.ApiType {
    if (std.mem.eql(u8, ty, "[]constu8") or std.mem.eql(u8, ty, "[]u8")) return .string;
    if (std.mem.eql(u8, ty, "i64")) return .int;
    if (std.mem.eql(u8, ty, "bool")) return .bool;
    return null;
}

fn parseLibReturnType(ty: []const u8) ?api.ApiType {
    if (std.mem.eql(u8, ty, "[]constu8") or std.mem.eql(u8, ty, "[]u8")) return .string;
    if (std.mem.eql(u8, ty, "i64")) return .int;
    if (std.mem.eql(u8, ty, "bool")) return .bool;
    if (std.mem.eql(u8, ty, "void")) return .void;
    return null;
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn isIdentContinue(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_';
}

fn lessString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
