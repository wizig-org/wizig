const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

pub fn appendScalarOutputCall(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    method: api.ApiMethod,
    symbol_name: []const u8,
    input_wire: helpers.WireKind,
    input_is_user_struct: bool,
    input_is_user_enum: bool,
    output_is_user_enum: bool,
) !void {
    switch (helpers.wireKind(method.output)) {
        .string => try appendStringOut(out, arena, symbol_name, input_wire, input_is_user_struct, input_is_user_enum),
        .int => {
            const call = if (output_is_user_enum) "callEnumOutput" else "callIntOutput";
            try appendValueOut(out, arena, symbol_name, call, "outValue", input_wire, input_is_user_struct, input_is_user_enum);
        },
        .bool => try appendValueOut(out, arena, symbol_name, "callBoolOutput", "outValue", input_wire, input_is_user_struct, input_is_user_enum),
        .void => try appendVoidOut(out, arena, symbol_name, input_wire, input_is_user_struct, input_is_user_enum),
    }
}

fn appendStringOut(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    sym: []const u8,
    input_wire: helpers.WireKind,
    input_is_struct: bool,
    input_is_enum: bool,
) !void {
    switch (input_wire) {
        .void => {
            try helpers.appendFmt(out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{sym});
            try helpers.appendFmt(out, arena, "            {s}(outPtr, outLen)\n", .{sym});
            try out.appendSlice(arena, "        }\n");
        },
        .string => if (input_is_struct) {
            try appendStructInStringOut(out, arena, sym);
        } else {
            try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
            try helpers.appendFmt(out, arena, "            try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{sym});
            try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, outPtr, outLen)\n", .{sym});
            try out.appendSlice(arena, "            }\n");
            try out.appendSlice(arena, "        }\n");
        },
        .int => {
            const arg: []const u8 = if (input_is_enum) "enumRawInput" else "input";
            try helpers.appendFmt(out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{sym});
            try helpers.appendFmt(out, arena, "            {s}({s}, outPtr, outLen)\n", .{ sym, arg });
            try out.appendSlice(arena, "        }\n");
        },
        .bool => {
            try helpers.appendFmt(out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{sym});
            try helpers.appendFmt(out, arena, "            {s}(inputFlag, outPtr, outLen)\n", .{sym});
            try out.appendSlice(arena, "        }\n");
        },
    }
}

fn appendValueOut(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    sym: []const u8,
    call: []const u8,
    out_arg: []const u8,
    input_wire: helpers.WireKind,
    input_is_struct: bool,
    input_is_enum: bool,
) !void {
    switch (input_wire) {
        .void => {
            try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ {s} in\n", .{ call, sym, out_arg });
            try helpers.appendFmt(out, arena, "            {s}({s})\n", .{ sym, out_arg });
            try out.appendSlice(arena, "        }\n");
        },
        .string => if (input_is_struct) {
            try appendStructInValueOut(out, arena, sym, call, out_arg);
        } else {
            try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
            try helpers.appendFmt(out, arena, "            try {s}(function: \"{s}\") {{ {s} in\n", .{ call, sym, out_arg });
            try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, {s})\n", .{ sym, out_arg });
            try out.appendSlice(arena, "            }\n");
            try out.appendSlice(arena, "        }\n");
        },
        .int => {
            const arg: []const u8 = if (input_is_enum) "enumRawInput" else "input";
            try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ {s} in\n", .{ call, sym, out_arg });
            try helpers.appendFmt(out, arena, "            {s}({s}, {s})\n", .{ sym, arg, out_arg });
            try out.appendSlice(arena, "        }\n");
        },
        .bool => {
            try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ {s} in\n", .{ call, sym, out_arg });
            try helpers.appendFmt(out, arena, "            {s}(inputFlag, {s})\n", .{ sym, out_arg });
            try out.appendSlice(arena, "        }\n");
        },
    }
}

fn appendVoidOut(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    sym: []const u8,
    input_wire: helpers.WireKind,
    input_is_struct: bool,
    input_is_enum: bool,
) !void {
    switch (input_wire) {
        .void => {
            try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{sym});
            try helpers.appendFmt(out, arena, "            {s}()\n", .{sym});
            try out.appendSlice(arena, "        }\n");
        },
        .string => if (input_is_struct) {
            try appendStructInVoidOut(out, arena, sym);
        } else {
            try out.appendSlice(arena, "        try withUTF8Pointer(input) { inputPtr, inputLen in\n");
            try helpers.appendFmt(out, arena, "            try callVoidOutput(function: \"{s}\") {{\n", .{sym});
            try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen)\n", .{sym});
            try out.appendSlice(arena, "            }\n");
            try out.appendSlice(arena, "        }\n");
        },
        .int => {
            const arg: []const u8 = if (input_is_enum) "enumRawInput" else "input";
            try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{sym});
            try helpers.appendFmt(out, arena, "            {s}({s})\n", .{ sym, arg });
            try out.appendSlice(arena, "        }\n");
        },
        .bool => {
            try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{sym});
            try helpers.appendFmt(out, arena, "            {s}(inputFlag)\n", .{sym});
            try out.appendSlice(arena, "        }\n");
        },
    }
}

fn appendStructInStringOut(out: *std.ArrayList(u8), arena: std.mem.Allocator, sym: []const u8) !void {
    try out.appendSlice(arena, "        return try withBinaryPointer(binaryInput) { inputPtr, inputLen in\n");
    try helpers.appendFmt(out, arena, "            return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{sym});
    try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, outPtr, outLen)\n", .{sym});
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n");
}

fn appendStructInValueOut(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    sym: []const u8,
    call: []const u8,
    out_arg: []const u8,
) !void {
    try out.appendSlice(arena, "        return try withBinaryPointer(binaryInput) { inputPtr, inputLen in\n");
    try helpers.appendFmt(out, arena, "            return try {s}(function: \"{s}\") {{ {s} in\n", .{ call, sym, out_arg });
    try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, {s})\n", .{ sym, out_arg });
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n");
}

fn appendStructInVoidOut(out: *std.ArrayList(u8), arena: std.mem.Allocator, sym: []const u8) !void {
    try out.appendSlice(arena, "        try withBinaryPointer(binaryInput) { inputPtr, inputLen in\n");
    try helpers.appendFmt(out, arena, "            try callVoidOutput(function: \"{s}\") {{\n", .{sym});
    try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen)\n", .{sym});
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n");
}
