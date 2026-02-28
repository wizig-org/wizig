const std = @import("std");
const Io = std.Io;
const fs_util = @import("../../support/fs.zig");
const path_util = @import("../../support/path.zig");
const targets = @import("targets.zig");

pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    var project_root: []const u8 = ".";
    var api_override: ?[]const u8 = null;

    var i: usize = 0;
    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
        project_root = args[i];
        i += 1;
    }

    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--api")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --api\n");
                return error.InvalidArguments;
            }
            api_override = args[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--api=")) {
            api_override = arg["--api=".len..];
            i += 1;
            continue;
        }
        try stderr.print("error: unknown codegen option '{s}'\n", .{arg});
        return error.InvalidArguments;
    }

    const root_abs = try path_util.resolveAbsolute(arena, io, project_root);
    const api_path = if (api_override) |value|
        try path_util.resolveAbsolute(arena, io, value)
    else
        try path_util.join(arena, root_abs, "ziggy.api.json");

    try generateProject(arena, io, stderr, stdout, root_abs, api_path);
}

pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    const ts_supported = targets.supportedNow(.typescript);
    try writer.writeAll(
        "Codegen:\n" ++
            "  ziggy codegen [project_root] [--api <path>]\n" ++
            "  # current targets: zig, swift, kotlin\n",
    );
    try writer.print("  # reserved target: typescript ({s})\n\n", .{if (ts_supported) "enabled" else "planned"});
}

pub fn generateProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: []const u8,
) !void {
    const text = std.Io.Dir.cwd().readFileAlloc(io, api_path, arena, .limited(1024 * 1024)) catch |err| {
        try stderr.print("error: failed to read API contract '{s}': {s}\n", .{ api_path, @errorName(err) });
        return error.CodegenFailed;
    };

    const spec = parseApiSpec(arena, text) catch |err| {
        try stderr.print("error: invalid API contract '{s}': {s}\n", .{ api_path, @errorName(err) });
        return error.CodegenFailed;
    };

    const generated_root = try path_util.join(arena, project_root, ".ziggy/generated");
    const zig_dir = try path_util.join(arena, generated_root, "zig");
    const swift_dir = try path_util.join(arena, generated_root, "swift");
    const kotlin_dir = try path_util.join(arena, generated_root, "kotlin/dev/ziggy/generated");

    try fs_util.ensureDir(io, zig_dir);
    try fs_util.ensureDir(io, swift_dir);
    try fs_util.ensureDir(io, kotlin_dir);

    const zig_out = try renderZigApi(arena, spec);
    const swift_out = try renderSwiftApi(arena, spec);
    const kotlin_out = try renderKotlinApi(arena, spec);

    const zig_file = try path_util.join(arena, zig_dir, "ZiggyGeneratedApi.zig");
    const swift_file = try path_util.join(arena, swift_dir, "ZiggyGeneratedApi.swift");
    const kotlin_file = try path_util.join(arena, kotlin_dir, "ZiggyGeneratedApi.kt");

    try fs_util.writeFileAtomically(io, zig_file, zig_out);
    try fs_util.writeFileAtomically(io, swift_file, swift_out);
    try fs_util.writeFileAtomically(io, kotlin_file, kotlin_out);

    try stdout.print("generated API bindings\n- {s}\n- {s}\n- {s}\n", .{ zig_file, swift_file, kotlin_file });
    try stdout.flush();
}

const ApiType = enum {
    string,
    int,
    bool,
    void,
};

const ApiMethod = struct {
    name: []const u8,
    input: ApiType,
    output: ApiType,
};

const ApiEvent = struct {
    name: []const u8,
    payload: ApiType,
};

const ApiSpec = struct {
    namespace: []const u8,
    methods: []ApiMethod,
    events: []ApiEvent,
};

fn parseApiSpec(arena: std.mem.Allocator, text: []const u8) !ApiSpec {
    const parsed = try std.json.parseFromSlice(std.json.Value, arena, text, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidContract;
    const root = parsed.value.object;

    const namespace = try dupRequiredString(arena, root, "namespace");
    errdefer arena.free(namespace);

    const methods_value = root.get("methods") orelse return error.InvalidContract;
    if (methods_value != .array) return error.InvalidContract;

    var methods = std.ArrayList(ApiMethod).empty;
    errdefer methods.deinit(arena);

    for (methods_value.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        const obj = item.object;

        const name = try dupRequiredString(arena, obj, "name");
        const input = try parseTypeField(obj, "input");
        const output = try parseTypeField(obj, "output");
        try methods.append(arena, .{ .name = name, .input = input, .output = output });
    }

    const events_value = root.get("events") orelse return error.InvalidContract;
    if (events_value != .array) return error.InvalidContract;

    var events = std.ArrayList(ApiEvent).empty;
    errdefer events.deinit(arena);

    for (events_value.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        const obj = item.object;

        const name = try dupRequiredString(arena, obj, "name");
        const payload = try parseTypeField(obj, "payload");
        try events.append(arena, .{ .name = name, .payload = payload });
    }

    return .{
        .namespace = namespace,
        .methods = try methods.toOwnedSlice(arena),
        .events = try events.toOwnedSlice(arena),
    };
}

fn dupRequiredString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    field: []const u8,
) ![]u8 {
    const value = object.get(field) orelse return error.InvalidContract;
    if (value != .string or value.string.len == 0) return error.InvalidContract;
    return allocator.dupe(u8, value.string);
}

fn parseTypeField(object: std.json.ObjectMap, field: []const u8) !ApiType {
    const value = object.get(field) orelse return error.InvalidContract;
    if (value != .string) return error.InvalidContract;
    if (std.mem.eql(u8, value.string, "string")) return .string;
    if (std.mem.eql(u8, value.string, "int")) return .int;
    if (std.mem.eql(u8, value.string, "bool")) return .bool;
    if (std.mem.eql(u8, value.string, "void")) return .void;
    return error.InvalidContract;
}

fn renderZigApi(arena: std.mem.Allocator, spec: ApiSpec) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `ziggy codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "const std = @import(\"std\");\n\n");

    try out.appendSlice(arena, "pub const ZiggyGeneratedApi = struct {\n");
    try out.appendSlice(arena, "    pub fn init() ZiggyGeneratedApi {\n");
    try out.appendSlice(arena, "        return .{};\n");
    try out.appendSlice(arena, "    }\n\n");

    for (spec.methods) |method| {
        const input_ty = zigType(method.input);
        const output_ty = zigType(method.output);
        if (method.output == .void) {
            try appendFmt(&out, arena, "    pub fn {s}(self: *const ZiggyGeneratedApi, input: {s}) void {{\n", .{ method.name, input_ty });
            try out.appendSlice(arena, "        _ = self;\n");
            try out.appendSlice(arena, "        _ = input;\n");
            try out.appendSlice(arena, "    }\n\n");
        } else {
            try appendFmt(&out, arena, "    pub fn {s}(self: *const ZiggyGeneratedApi, input: {s}, allocator: std.mem.Allocator) !{s} {{\n", .{ method.name, input_ty, output_ty });
            try out.appendSlice(arena, "        _ = self;\n");
            try out.appendSlice(arena, "        _ = allocator;\n");
            if (method.output == .string and method.input == .string) {
                try out.appendSlice(arena, "        return allocator.dupe(u8, input);\n");
            } else {
                try appendFmt(&out, arena, "        _ = input;\n        return {s};\n", .{zigDefaultValue(method.output)});
            }
            try out.appendSlice(arena, "    }\n\n");
        }
    }

    try out.appendSlice(arena, "};\n");
    return out.toOwnedSlice(arena);
}

fn renderSwiftApi(arena: std.mem.Allocator, spec: ApiSpec) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `ziggy codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "import Foundation\n\n");

    try out.appendSlice(arena, "public protocol ZiggyGeneratedEventSink: AnyObject {\n");
    for (spec.events) |event| {
        const event_name = try upperCamel(arena, event.name);
        try appendFmt(&out, arena, "    func on{s}(payload: {s})\n", .{ event_name, swiftType(event.payload) });
    }
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "public final class ZiggyGeneratedApi {\n");
    try out.appendSlice(arena, "    public weak var sink: ZiggyGeneratedEventSink?\n");
    try out.appendSlice(arena, "    public init() {}\n\n");

    for (spec.methods) |method| {
        const input_ty = swiftType(method.input);
        const output_ty = swiftType(method.output);
        if (method.output == .void) {
            try appendFmt(&out, arena, "    public func {s}(_ input: {s}) {{\n", .{ method.name, input_ty });
            try out.appendSlice(arena, "        _ = input\n");
            try out.appendSlice(arena, "    }\n\n");
        } else {
            try appendFmt(&out, arena, "    public func {s}(_ input: {s}) throws -> {s} {{\n", .{ method.name, input_ty, output_ty });
            if (method.output == .string and method.input == .string) {
                try out.appendSlice(arena, "        return input\n");
            } else {
                try appendFmt(&out, arena, "        _ = input\n        return {s}\n", .{swiftDefaultValue(method.output)});
            }
            try out.appendSlice(arena, "    }\n\n");
        }
    }

    for (spec.events) |event| {
        const event_name = try upperCamel(arena, event.name);
        try appendFmt(&out, arena, "    public func emit{s}(payload: {s}) {{\n", .{ event_name, swiftType(event.payload) });
        try appendFmt(&out, arena, "        sink?.on{s}(payload: payload)\n", .{event_name});
        try out.appendSlice(arena, "    }\n\n");
    }

    try out.appendSlice(arena, "}\n");
    return out.toOwnedSlice(arena);
}

fn renderKotlinApi(arena: std.mem.Allocator, spec: ApiSpec) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `ziggy codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "package dev.ziggy.generated\n\n");

    try out.appendSlice(arena, "interface ZiggyGeneratedEventSink {\n");
    for (spec.events) |event| {
        try appendFmt(&out, arena, "    fun on{s}(payload: {s})\n", .{ try upperCamel(arena, event.name), kotlinType(event.payload) });
    }
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "class ZiggyGeneratedApi(private var sink: ZiggyGeneratedEventSink? = null) {\n");
    try out.appendSlice(arena, "    fun setEventSink(next: ZiggyGeneratedEventSink?) {\n");
    try out.appendSlice(arena, "        sink = next\n");
    try out.appendSlice(arena, "    }\n\n");

    for (spec.methods) |method| {
        if (method.output == .void) {
            try appendFmt(&out, arena, "    fun {s}(input: {s}) {{\n", .{ method.name, kotlinType(method.input) });
            try out.appendSlice(arena, "        val _unused = input\n");
            try out.appendSlice(arena, "    }\n\n");
        } else {
            try appendFmt(&out, arena, "    fun {s}(input: {s}): {s} {{\n", .{ method.name, kotlinType(method.input), kotlinType(method.output) });
            if (method.output == .string and method.input == .string) {
                try out.appendSlice(arena, "        return input\n");
            } else {
                try appendFmt(&out, arena, "        val _unused = input\n        return {s}\n", .{kotlinDefaultValue(method.output)});
            }
            try out.appendSlice(arena, "    }\n\n");
        }
    }

    for (spec.events) |event| {
        const event_name = try upperCamel(arena, event.name);
        try appendFmt(&out, arena, "    fun emit{s}(payload: {s}) {{\n", .{ event_name, kotlinType(event.payload) });
        try appendFmt(&out, arena, "        sink?.on{s}(payload)\n", .{event_name});
        try out.appendSlice(arena, "    }\n\n");
    }

    try out.appendSlice(arena, "}\n");
    return out.toOwnedSlice(arena);
}

fn zigType(value: ApiType) []const u8 {
    return switch (value) {
        .string => "[]const u8",
        .int => "i64",
        .bool => "bool",
        .void => "void",
    };
}

fn swiftType(value: ApiType) []const u8 {
    return switch (value) {
        .string => "String",
        .int => "Int64",
        .bool => "Bool",
        .void => "Void",
    };
}

fn kotlinType(value: ApiType) []const u8 {
    return switch (value) {
        .string => "String",
        .int => "Long",
        .bool => "Boolean",
        .void => "Unit",
    };
}

fn zigDefaultValue(value: ApiType) []const u8 {
    return switch (value) {
        .string => "\"\"",
        .int => "0",
        .bool => "false",
        .void => "{}",
    };
}

fn swiftDefaultValue(value: ApiType) []const u8 {
    return switch (value) {
        .string => "\"\"",
        .int => "0",
        .bool => "false",
        .void => "()",
    };
}

fn kotlinDefaultValue(value: ApiType) []const u8 {
    return switch (value) {
        .string => "\"\"",
        .int => "0L",
        .bool => "false",
        .void => "Unit",
    };
}

fn upperCamel(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var uppercase_next = true;
    for (input) |ch| {
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch))) {
            uppercase_next = true;
            continue;
        }
        if (uppercase_next) {
            try out.append(allocator, std.ascii.toUpper(ch));
        } else {
            try out.append(allocator, ch);
        }
        uppercase_next = false;
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "Event");
    }

    return out.toOwnedSlice(allocator);
}

fn appendFmt(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const rendered = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(rendered);
    try out.appendSlice(allocator, rendered);
}
