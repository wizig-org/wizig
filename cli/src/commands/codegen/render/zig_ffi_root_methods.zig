//! Per-method FFI export generation for `WizigGeneratedFfiRoot.zig`.

const std = @import("std");
const api = @import("../model/api.zig");
const helpers = @import("helpers.zig");

pub fn appendMethodExports(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
    for (methods) |method| {
        const export_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});

        if (method.output == .string) {
            switch (method.input) {
                .void => {
                    try helpers.appendFmt(out, arena, "pub export fn {s}(out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {{\n", .{export_name});
                    try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
                    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
                    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
                    try out.appendSlice(arena, "    output_ptr.* = null;\n");
                    try out.appendSlice(arena, "    output_len.* = 0;\n");
                    try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(allocator)) catch |err| return mapError(err);\n", .{method.name});
                },
                .string => {
                    try helpers.appendFmt(out, arena, "pub export fn {s}(input_ptr: [*]const u8, input_len: usize, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {{\n", .{export_name});
                    try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
                    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
                    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
                    try out.appendSlice(arena, "    output_ptr.* = null;\n");
                    try out.appendSlice(arena, "    output_len.* = 0;\n");
                    try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
                    try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input, allocator)) catch |err| return mapError(err);\n", .{method.name});
                },
                .int => {
                    try helpers.appendFmt(out, arena, "pub export fn {s}(input: i64, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {{\n", .{export_name});
                    try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
                    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
                    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
                    try out.appendSlice(arena, "    output_ptr.* = null;\n");
                    try out.appendSlice(arena, "    output_len.* = 0;\n");
                    try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input, allocator)) catch |err| return mapError(err);\n", .{method.name});
                },
                .bool => {
                    try helpers.appendFmt(out, arena, "pub export fn {s}(input: u8, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {{\n", .{export_name});
                    try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
                    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
                    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
                    try out.appendSlice(arena, "    output_ptr.* = null;\n");
                    try out.appendSlice(arena, "    output_len.* = 0;\n");
                    try out.appendSlice(arena, "    const input_bool = input != 0;\n");
                    try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input_bool, allocator)) catch |err| return mapError(err);\n", .{method.name});
                },
            }

            try out.appendSlice(arena, "    const owned = allocator.dupe(u8, value) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
            try out.appendSlice(arena, "    output_ptr.* = owned.ptr;\n");
            try out.appendSlice(arena, "    output_len.* = owned.len;\n");
            try out.appendSlice(arena, "    clearLastError();\n");
            try out.appendSlice(arena, "    return statusCode(.ok);\n");
            try out.appendSlice(arena, "}\n\n");
            continue;
        }

        if (method.output == .int) {
            switch (method.input) {
                .void => try helpers.appendFmt(out, arena, "pub export fn {s}(out_value: ?*i64) i32 {{\n", .{export_name}),
                .string => try helpers.appendFmt(out, arena, "pub export fn {s}(input_ptr: [*]const u8, input_len: usize, out_value: ?*i64) i32 {{\n", .{export_name}),
                .int => try helpers.appendFmt(out, arena, "pub export fn {s}(input: i64, out_value: ?*i64) i32 {{\n", .{export_name}),
                .bool => try helpers.appendFmt(out, arena, "pub export fn {s}(input: u8, out_value: ?*i64) i32 {{\n", .{export_name}),
            }
            try out.appendSlice(arena, "    if (out_value == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
            if (method.input == .string) {
                try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
            } else if (method.input == .bool) {
                try out.appendSlice(arena, "    const input_bool = input != 0;\n");
            }
            switch (method.input) {
                .void => try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}()) catch |err| return mapError(err);\n", .{method.name}),
                .string => try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
                .int => try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
                .bool => try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input_bool)) catch |err| return mapError(err);\n", .{method.name}),
            }
            try out.appendSlice(arena, "    out_value.?.* = value;\n");
            try out.appendSlice(arena, "    clearLastError();\n");
            try out.appendSlice(arena, "    return statusCode(.ok);\n");
            try out.appendSlice(arena, "}\n\n");
            continue;
        }

        if (method.output == .bool) {
            switch (method.input) {
                .void => try helpers.appendFmt(out, arena, "pub export fn {s}(out_value: ?*u8) i32 {{\n", .{export_name}),
                .string => try helpers.appendFmt(out, arena, "pub export fn {s}(input_ptr: [*]const u8, input_len: usize, out_value: ?*u8) i32 {{\n", .{export_name}),
                .int => try helpers.appendFmt(out, arena, "pub export fn {s}(input: i64, out_value: ?*u8) i32 {{\n", .{export_name}),
                .bool => try helpers.appendFmt(out, arena, "pub export fn {s}(input: u8, out_value: ?*u8) i32 {{\n", .{export_name}),
            }
            try out.appendSlice(arena, "    if (out_value == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
            if (method.input == .string) {
                try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
            } else if (method.input == .bool) {
                try out.appendSlice(arena, "    const input_bool = input != 0;\n");
            }
            switch (method.input) {
                .void => try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}()) catch |err| return mapError(err);\n", .{method.name}),
                .string => try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
                .int => try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
                .bool => try helpers.appendFmt(out, arena, "    const value = unwrapResult(app.{s}(input_bool)) catch |err| return mapError(err);\n", .{method.name}),
            }
            try out.appendSlice(arena, "    out_value.?.* = if (value) 1 else 0;\n");
            try out.appendSlice(arena, "    clearLastError();\n");
            try out.appendSlice(arena, "    return statusCode(.ok);\n");
            try out.appendSlice(arena, "}\n\n");
            continue;
        }

        switch (method.input) {
            .void => try helpers.appendFmt(out, arena, "pub export fn {s}() i32 {{\n", .{export_name}),
            .string => try helpers.appendFmt(out, arena, "pub export fn {s}(input_ptr: [*]const u8, input_len: usize) i32 {{\n", .{export_name}),
            .int => try helpers.appendFmt(out, arena, "pub export fn {s}(input: i64) i32 {{\n", .{export_name}),
            .bool => try helpers.appendFmt(out, arena, "pub export fn {s}(input: u8) i32 {{\n", .{export_name}),
        }

        if (method.input == .string) {
            try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
        } else if (method.input == .bool) {
            try out.appendSlice(arena, "    const input_bool = input != 0;\n");
        }

        switch (method.input) {
            .void => try helpers.appendFmt(out, arena, "    _ = unwrapResult(app.{s}()) catch |err| return mapError(err);\n", .{method.name}),
            .string => try helpers.appendFmt(out, arena, "    _ = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
            .int => try helpers.appendFmt(out, arena, "    _ = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
            .bool => try helpers.appendFmt(out, arena, "    _ = unwrapResult(app.{s}(input_bool)) catch |err| return mapError(err);\n", .{method.name}),
        }
        try out.appendSlice(arena, "    clearLastError();\n");
        try out.appendSlice(arena, "    return statusCode(.ok);\n");
        try out.appendSlice(arena, "}\n\n");
    }
}
