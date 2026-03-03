//! Contract parsers for `wizig.api.zig` and `wizig.api.json`.

const std = @import("std");
const api = @import("../model/api.zig");

pub fn parseApiSpecFromZig(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
    var namespace: ?[]u8 = null;
    var methods = std.ArrayList(api.ApiMethod).empty;
    var events = std.ArrayList(api.ApiEvent).empty;

    errdefer {
        if (namespace) |value| arena.free(value);
        for (methods.items) |method| arena.free(method.name);
        methods.deinit(arena);
        for (events.items) |event| arena.free(event.name);
        events.deinit(arena);
    }

    const Section = enum { none, methods, events };
    var section: Section = .none;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "//")) continue;

        if (std.mem.startsWith(u8, line, "pub const namespace = ")) {
            const value = try extractQuotedField(arena, line, "pub const namespace = \"");
            if (namespace) |old| arena.free(old);
            namespace = value;
            continue;
        }

        if (std.mem.startsWith(u8, line, "pub const methods = .{")) {
            section = .methods;
            continue;
        }

        if (std.mem.startsWith(u8, line, "pub const events = .{")) {
            section = .events;
            continue;
        }

        if (std.mem.eql(u8, line, "};")) {
            section = .none;
            continue;
        }

        if (!std.mem.startsWith(u8, line, ".{")) continue;

        switch (section) {
            .methods => {
                const name = try extractQuotedField(arena, line, ".name = \"");
                const input = try parseTypeToken(try extractEnumToken(line, ".input = ."));
                const output = try parseTypeToken(try extractEnumToken(line, ".output = ."));
                try methods.append(arena, .{ .name = name, .input = input, .output = output });
            },
            .events => {
                const name = try extractQuotedField(arena, line, ".name = \"");
                const payload = try parseTypeToken(try extractEnumToken(line, ".payload = ."));
                try events.append(arena, .{ .name = name, .payload = payload });
            },
            .none => {},
        }
    }

    return .{
        .namespace = namespace orelse return error.InvalidContract,
        .methods = try methods.toOwnedSlice(arena),
        .events = try events.toOwnedSlice(arena),
    };
}

pub fn parseApiSpecFromJson(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
    const parsed = try std.json.parseFromSlice(std.json.Value, arena, text, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidContract;
    const root = parsed.value.object;

    const namespace = try dupRequiredString(arena, root, "namespace");
    errdefer arena.free(namespace);

    const methods_value = root.get("methods") orelse return error.InvalidContract;
    if (methods_value != .array) return error.InvalidContract;

    var methods = std.ArrayList(api.ApiMethod).empty;
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

    var events = std.ArrayList(api.ApiEvent).empty;
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

fn extractQuotedField(arena: std.mem.Allocator, line: []const u8, prefix: []const u8) ![]u8 {
    const start = std.mem.indexOf(u8, line, prefix) orelse return error.InvalidContract;
    const rest = line[start + prefix.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return error.InvalidContract;
    if (end == 0) return error.InvalidContract;
    return arena.dupe(u8, rest[0..end]);
}

fn extractEnumToken(line: []const u8, marker: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, line, marker) orelse return error.InvalidContract;
    const rest = line[start + marker.len ..];

    var end: usize = 0;
    while (end < rest.len) : (end += 1) {
        const ch = rest[end];
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_')) break;
    }
    if (end == 0) return error.InvalidContract;
    return rest[0..end];
}

fn parseTypeToken(token: []const u8) !api.ApiType {
    if (std.mem.eql(u8, token, "string")) return .string;
    if (std.mem.eql(u8, token, "int")) return .int;
    if (std.mem.eql(u8, token, "bool")) return .bool;
    if (std.mem.eql(u8, token, "void")) return .void;
    return error.InvalidContract;
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

fn parseTypeField(object: std.json.ObjectMap, field: []const u8) !api.ApiType {
    const value = object.get(field) orelse return error.InvalidContract;
    if (value != .string) return error.InvalidContract;
    return parseTypeToken(value.string);
}
