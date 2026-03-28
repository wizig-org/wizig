const std = @import("std");
const api = @import("../model/api.zig");
const helpers = @import("helpers.zig");

pub fn appendApiMethodForwarders(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
) !void {
    for (spec.methods) |method| {
        try appendApiMethodForwarder(out, arena, method);
    }
}

fn appendApiMethodForwarder(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    method: api.ApiMethod,
) !void {
    const params = try buildMethodParams(arena, method);
    const call_args = try buildMethodCallArgs(arena, method);
    const symbol = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});

    try helpers.appendFmt(out, arena, "int32_t {s}({s}) {{\n", .{ symbol, params });
    try helpers.appendFmt(out, arena, "    typedef int32_t (*fn_t)({s});\n", .{params});
    try helpers.appendFmt(out, arena, "    fn_t fn = (fn_t)wizigffi_resolve(\"{s}\");\n", .{symbol});
    if (call_args.len == 0) {
        try out.appendSlice(arena, "    return fn != NULL ? fn() : -1;\n");
    } else {
        try helpers.appendFmt(out, arena, "    return fn != NULL ? fn({s}) : -1;\n", .{call_args});
    }
    try out.appendSlice(arena, "}\n\n");
}

fn buildMethodParams(arena: std.mem.Allocator, method: api.ApiMethod) ![]const u8 {
    var params = std.ArrayList(u8).empty;
    var need_comma = false;

    switch (helpers.wireKind(method.input)) {
        .void => {},
        .string => {
            try params.appendSlice(arena, "const uint8_t* input_ptr, size_t input_len");
            need_comma = true;
        },
        .int => {
            try params.appendSlice(arena, "int64_t input");
            need_comma = true;
        },
        .bool => {
            try params.appendSlice(arena, "uint8_t input");
            need_comma = true;
        },
    }

    switch (helpers.wireKind(method.output)) {
        .void => {},
        .string => {
            if (need_comma) try params.appendSlice(arena, ", ");
            try params.appendSlice(arena, "uint8_t** out_ptr, size_t* out_len");
        },
        .int => {
            if (need_comma) try params.appendSlice(arena, ", ");
            try params.appendSlice(arena, "int64_t* out_value");
        },
        .bool => {
            if (need_comma) try params.appendSlice(arena, ", ");
            try params.appendSlice(arena, "uint8_t* out_value");
        },
    }

    return params.toOwnedSlice(arena);
}

fn buildMethodCallArgs(arena: std.mem.Allocator, method: api.ApiMethod) ![]const u8 {
    var args = std.ArrayList(u8).empty;
    var need_comma = false;

    switch (helpers.wireKind(method.input)) {
        .void => {},
        .string => {
            try args.appendSlice(arena, "input_ptr, input_len");
            need_comma = true;
        },
        .int, .bool => {
            try args.appendSlice(arena, "input");
            need_comma = true;
        },
    }

    switch (helpers.wireKind(method.output)) {
        .void => {},
        .string => {
            if (need_comma) try args.appendSlice(arena, ", ");
            try args.appendSlice(arena, "out_ptr, out_len");
        },
        .int, .bool => {
            if (need_comma) try args.appendSlice(arena, ", ");
            try args.appendSlice(arena, "out_value");
        },
    }

    return args.toOwnedSlice(arena);
}
