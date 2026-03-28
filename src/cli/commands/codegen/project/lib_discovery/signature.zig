//! Signature parsing and API method discovery for `lib/**/*.zig`.
const std = @import("std");

const api = @import("../../model/api.zig");
const files = @import("files.zig");
const fs_util = @import("../../../../support/fs.zig");
const path_util = @import("../../../../support/path.zig");

/// Discovers API methods from `lib/**/*.zig`, resolving known user-defined types.
pub fn discoverLibApiMethodsWithTypes(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiMethod {
    const lib_sources = try files.discoverLibSourcePaths(arena, io, project_root);
    if (lib_sources.len == 0) return &.{};

    const lib_dir = try path_util.join(arena, project_root, "lib");
    var discovered = std.ArrayList(api.ApiMethod).empty;
    errdefer discovered.deinit(arena);

    for (lib_sources) |rel_path| {
        const abs_path = try path_util.join(arena, lib_dir, rel_path);
        const source = std.Io.Dir.cwd().readFileAlloc(io, abs_path, arena, .limited(2 * 1024 * 1024)) catch continue;
        const methods = try parseLibApiMethodsFromSource(arena, source, known_struct_names, known_enum_names);
        for (methods) |method| {
            try appendUniqueMethod(arena, &discovered, method);
        }
    }

    return discovered.toOwnedSlice(arena);
}

fn parseLibApiMethodsFromSource(
    arena: std.mem.Allocator,
    source: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiMethod {
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

        if (try methodFromLibSignature(
            arena,
            name,
            source[params_start..params_end],
            return_raw,
            known_struct_names,
            known_enum_names,
        )) |method| {
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
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
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
                input_type = classifyParamType(param_types.items[0], known_struct_names, known_enum_names) orelse return null;
            }
        },
        2 => {
            input_type = classifyParamType(param_types.items[0], known_struct_names, known_enum_names) orelse return null;
            if (!isAllocatorType(param_types.items[1])) return null;
            allocator_param = true;
        },
        else => return null,
    }

    var ret = std.mem.trim(u8, return_raw, " \t\r\n");
    if (ret.len == 0) return null;
    if (ret[0] == '!') ret = std.mem.trim(u8, ret[1..], " \t\r\n");
    const ret_norm = try normalizeTypeToken(arena, ret);
    const output_type = classifyReturnType(ret_norm, known_struct_names, known_enum_names) orelse return null;

    const needs_alloc = output_type == .string;
    if (needs_alloc and !allocator_param) return null;
    if (!needs_alloc and allocator_param) return null;

    return .{
        .name = try arena.dupe(u8, name),
        .input = input_type,
        .output = output_type,
    };
}

fn appendUniqueMethod(
    arena: std.mem.Allocator,
    methods: *std.ArrayList(api.ApiMethod),
    method: api.ApiMethod,
) !void {
    for (methods.items) |existing| {
        if (std.mem.eql(u8, existing.name, method.name)) return;
    }
    try methods.append(arena, method);
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

fn classifyParamType(
    ty: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ?api.ApiType {
    if (std.mem.eql(u8, ty, "[]constu8") or std.mem.eql(u8, ty, "[]u8")) return .string;
    if (std.mem.eql(u8, ty, "i64")) return .int;
    if (std.mem.eql(u8, ty, "bool")) return .bool;
    for (known_struct_names) |name| {
        if (std.mem.eql(u8, ty, name)) return .{ .user_struct = name };
    }
    for (known_enum_names) |name| {
        if (std.mem.eql(u8, ty, name)) return .{ .user_enum = name };
    }
    return null;
}

fn classifyReturnType(
    ty: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ?api.ApiType {
    if (std.mem.eql(u8, ty, "[]constu8") or std.mem.eql(u8, ty, "[]u8")) return .string;
    if (std.mem.eql(u8, ty, "i64")) return .int;
    if (std.mem.eql(u8, ty, "bool")) return .bool;
    if (std.mem.eql(u8, ty, "void")) return .void;
    for (known_struct_names) |name| {
        if (std.mem.eql(u8, ty, name)) return .{ .user_struct = name };
    }
    for (known_enum_names) |name| {
        if (std.mem.eql(u8, ty, name)) return .{ .user_enum = name };
    }
    return null;
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn isIdentContinue(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_';
}

test "normalizeTypeToken strips whitespace" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const normalized = try normalizeTypeToken(arena, " [] const u8 ");
    try std.testing.expectEqualStrings("[]constu8", normalized);
}

test "classify helpers recognize primitives and known names" {
    const known_structs = [_][]const u8{"MyStruct"};
    const known_enums = [_][]const u8{"MyEnum"};

    try std.testing.expect(switch (classifyParamType("[]constu8", &known_structs, &known_enums) orelse unreachable) {
        .string => true,
        else => false,
    });
    try std.testing.expect(switch (classifyParamType("i64", &known_structs, &known_enums) orelse unreachable) {
        .int => true,
        else => false,
    });
    try std.testing.expect(switch (classifyParamType("bool", &known_structs, &known_enums) orelse unreachable) {
        .bool => true,
        else => false,
    });

    const struct_type = classifyParamType("MyStruct", &known_structs, &known_enums) orelse unreachable;
    try std.testing.expectEqualStrings("MyStruct", struct_type.user_struct);

    const enum_type = classifyReturnType("MyEnum", &known_structs, &known_enums) orelse unreachable;
    try std.testing.expectEqualStrings("MyEnum", enum_type.user_enum);
    try std.testing.expect(switch (classifyReturnType("void", &known_structs, &known_enums) orelse unreachable) {
        .void => true,
        else => false,
    });
}

test "discoverLibApiMethodsWithTypes deduplicates method names across files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    const project_root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/sample-app", .{tmp.sub_path});
    const lib_dir = try path_util.join(arena, project_root, "lib");
    try std.Io.Dir.cwd().createDirPath(io, lib_dir);

    try fs_util.writeFileAtomically(io, try path_util.join(arena, lib_dir, "a.zig"), "pub fn answer() i64 { return 1; }\n");
    try fs_util.writeFileAtomically(io, try path_util.join(arena, lib_dir, "b.zig"), "pub fn answer() i64 { return 2; }\n");
    try fs_util.writeFileAtomically(io, try path_util.join(arena, lib_dir, "c.zig"), "pub fn fetch(allocator: std.mem.Allocator) []const u8 { return \"\"; }\n");

    const methods = try discoverLibApiMethodsWithTypes(arena, io, project_root, &.{}, &.{});
    try std.testing.expectEqual(@as(usize, 2), methods.len);
    try std.testing.expectEqualStrings("answer", methods[0].name);
    try std.testing.expectEqualStrings("fetch", methods[1].name);
    try std.testing.expect(switch (methods[0].output) {
        .int => true,
        else => false,
    });
    try std.testing.expect(switch (methods[1].output) {
        .string => true,
        else => false,
    });
}
