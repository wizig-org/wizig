const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

pub fn appendBinaryOutputCall(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    method: api.ApiMethod,
    symbol_name: []const u8,
    input_wire: helpers.WireKind,
    input_is_user_struct: bool,
    input_is_user_enum: bool,
) !void {
    const struct_name = switch (method.output) {
        .user_struct => |name| name,
        else => unreachable,
    };

    switch (input_wire) {
        .void => {
            try helpers.appendFmt(out, arena, "        return try callBinaryOutput(function: \"{s}\", decode: {s}.fromBinary) {{ outPtr, outLen in\n", .{ symbol_name, struct_name });
            try helpers.appendFmt(out, arena, "            {s}(outPtr, outLen)\n", .{symbol_name});
            try out.appendSlice(arena, "        }\n");
        },
        .string => if (input_is_user_struct) {
            try appendBinaryInputWrapper(out, arena, symbol_name, struct_name, "outPtr, outLen");
        } else {
            try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
            try helpers.appendFmt(out, arena, "            try callBinaryOutput(function: \"{s}\", decode: {s}.fromBinary) {{ outPtr, outLen in\n", .{ symbol_name, struct_name });
            try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, outPtr, outLen)\n", .{symbol_name});
            try out.appendSlice(arena, "            }\n");
            try out.appendSlice(arena, "        }\n");
        },
        .int => {
            const arg: []const u8 = if (input_is_user_enum) "enumRawInput" else "input";
            try helpers.appendFmt(out, arena, "        return try callBinaryOutput(function: \"{s}\", decode: {s}.fromBinary) {{ outPtr, outLen in\n", .{ symbol_name, struct_name });
            try helpers.appendFmt(out, arena, "            {s}({s}, outPtr, outLen)\n", .{ symbol_name, arg });
            try out.appendSlice(arena, "        }\n");
        },
        .bool => {
            try helpers.appendFmt(out, arena, "        return try callBinaryOutput(function: \"{s}\", decode: {s}.fromBinary) {{ outPtr, outLen in\n", .{ symbol_name, struct_name });
            try helpers.appendFmt(out, arena, "            {s}(inputFlag, outPtr, outLen)\n", .{symbol_name});
            try out.appendSlice(arena, "        }\n");
        },
    }
}

fn appendBinaryInputWrapper(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    symbol_name: []const u8,
    struct_name: []const u8,
    out_args: []const u8,
) !void {
    try out.appendSlice(arena, "        return try withBinaryPointer(binaryInput) { inputPtr, inputLen in\n");
    try helpers.appendFmt(out, arena, "            return try callBinaryOutput(function: \"{s}\", decode: {s}.fromBinary) {{ {s} in\n", .{ symbol_name, struct_name, out_args });
    try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, {s})\n", .{ symbol_name, out_args });
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n");
}
