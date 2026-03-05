//! Per-method FFI export generation for `WizigGeneratedFfiRoot.zig`.
//!
//! Wire mapping:
//! - `user_enum`   <-> `i64` ordinal
//! - `user_struct` <-> UTF-8 JSON bytes over existing string ABI

const std = @import("std");
const api = @import("../model/api.zig");
const helpers = @import("helpers.zig");

/// Appends generated export functions for every discovered API method.
pub fn appendMethodExports(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
    for (methods) |method| {
        const export_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});

        try appendSignature(out, arena, export_name, method);
        try appendOutputGuards(out, arena, method.output);
        const call_arg = try appendInputSetup(out, arena, method.input);
        try appendInvocation(out, arena, method, call_arg);
        try appendOutputMarshalling(out, arena, method.output);
        try out.appendSlice(arena, "    clearLastError();\n");
        try out.appendSlice(arena, "    return statusCode(.ok);\n");
        try out.appendSlice(arena, "}\n\n");
    }
}

fn appendSignature(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    export_name: []const u8,
    method: api.ApiMethod,
) !void {
    try helpers.appendFmt(out, arena, "pub export fn {s}(", .{export_name});

    var need_comma = false;
    switch (helpers.wireKind(method.input)) {
        .void => {},
        .string => {
            try out.appendSlice(arena, "input_ptr: [*]const u8, input_len: usize");
            need_comma = true;
        },
        .int => {
            try out.appendSlice(arena, "input: i64");
            need_comma = true;
        },
        .bool => {
            try out.appendSlice(arena, "input: u8");
            need_comma = true;
        },
    }

    switch (helpers.wireKind(method.output)) {
        .void => {},
        .string => {
            if (need_comma) try out.appendSlice(arena, ", ");
            try out.appendSlice(arena, "out_ptr: ?*?[*]u8, out_len: ?*usize");
        },
        .int => {
            if (need_comma) try out.appendSlice(arena, ", ");
            try out.appendSlice(arena, "out_value: ?*i64");
        },
        .bool => {
            if (need_comma) try out.appendSlice(arena, ", ");
            try out.appendSlice(arena, "out_value: ?*u8");
        },
    }

    try out.appendSlice(arena, ") i32 {\n");
}

fn appendOutputGuards(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    output: api.ApiType,
) !void {
    switch (helpers.wireKind(output)) {
        .void => {},
        .string => {
            try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
            try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
            try out.appendSlice(arena, "    const output_len = out_len.?;\n");
            try out.appendSlice(arena, "    output_ptr.* = null;\n");
            try out.appendSlice(arena, "    output_len.* = 0;\n");
        },
        .int, .bool => {
            try out.appendSlice(arena, "    if (out_value == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
        },
    }
}

fn appendInputSetup(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    input: api.ApiType,
) !?[]const u8 {
    return switch (input) {
        .void => null,
        .string => blk: {
            try out.appendSlice(arena, "    const input_value = input_ptr[0..input_len];\n");
            break :blk "input_value";
        },
        .int => "input",
        .bool => blk: {
            try out.appendSlice(arena, "    const input_value = input != 0;\n");
            break :blk "input_value";
        },
        .user_enum => |name| blk: {
            try helpers.appendFmt(
                out,
                arena,
                "    const input_value = std.meta.intToEnum({s}, input) catch return setLastError(.argument, statusCode(.invalid_argument), \"invalid enum ordinal\");\n",
                .{name},
            );
            break :blk "input_value";
        },
        .user_struct => |name| blk: {
            try out.appendSlice(arena, "    const input_json = input_ptr[0..input_len];\n");
            try helpers.appendFmt(
                out,
                arena,
                "    const parsed_input = std.json.parseFromSlice({s}, bootstrap_allocator, input_json, .{{}}) catch return setLastError(.argument, statusCode(.invalid_argument), \"invalid json input\");\n",
                .{name},
            );
            try out.appendSlice(arena, "    defer parsed_input.deinit();\n");
            break :blk "parsed_input.value";
        },
    };
}

fn appendInvocation(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    method: api.ApiMethod,
    maybe_arg: ?[]const u8,
) !void {
    const name = method.name;
    if (method.output == .string) {
        if (maybe_arg) |arg| {
            try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}({s}, bootstrap_allocator)) catch |err| return mapError(err);\n", .{ name, arg });
        } else {
            try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(bootstrap_allocator)) catch |err| return mapError(err);\n", .{name});
        }
        return;
    }

    if (method.output == .void) {
        if (maybe_arg) |arg| {
            try helpers.appendFmt(out, arena, "    _ = unwrapResult(app.{s}({s})) catch |err| return mapError(err);\n", .{ name, arg });
        } else {
            try helpers.appendFmt(out, arena, "    _ = unwrapResult(app.{s}()) catch |err| return mapError(err);\n", .{name});
        }
        return;
    }

    if (maybe_arg) |arg| {
        try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}({s})) catch |err| return mapError(err);\n", .{ name, arg });
    } else {
        try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}()) catch |err| return mapError(err);\n", .{name});
    }
}

fn appendOutputMarshalling(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    output: api.ApiType,
) !void {
    switch (helpers.wireKind(output)) {
        .void => {},
        .string => {
            if (output == .user_struct) {
                try out.appendSlice(arena, "    var json_out: std.Io.Writer.Allocating = .init(bootstrap_allocator);\n");
                try out.appendSlice(arena, "    defer json_out.deinit();\n");
                try out.appendSlice(arena, "    std.json.Stringify.value(value, .{}, &json_out.writer) catch return setLastError(.runtime, statusCode(.internal_error), \"json encode failed\");\n");
                try out.appendSlice(arena, "    const encoded = json_out.written();\n");
                try out.appendSlice(arena, "    const owned = bootstrap_allocator.dupe(u8, encoded) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
            } else {
                try out.appendSlice(arena, "    const owned = bootstrap_allocator.dupe(u8, value) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
            }
            try out.appendSlice(arena, "    output_ptr.* = owned.ptr;\n");
            try out.appendSlice(arena, "    output_len.* = owned.len;\n");
        },
        .int => {
            if (output == .user_enum) {
                try out.appendSlice(arena, "    out_value.?.* = @intFromEnum(value);\n");
            } else {
                try out.appendSlice(arena, "    out_value.?.* = value;\n");
            }
        },
        .bool => {
            try out.appendSlice(arena, "    out_value.?.* = if (value) 1 else 0;\n");
        },
    }
}
