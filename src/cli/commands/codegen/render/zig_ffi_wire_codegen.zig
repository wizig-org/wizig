//! Binary wire format code generation helpers for struct marshalling.
//!
//! Emits wire-format read (decode) and write (encode) code for
//! user-defined structs, reading/writing fields in contract order
//! using the binary wire format v1.

const std = @import("std");
const api = @import("../model/api.zig");
const helpers = @import("helpers.zig");

/// Finds a struct definition by name in the known struct list.
pub fn findStruct(structs: []const api.UserStruct, name: []const u8) ?api.UserStruct {
    for (structs) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

/// Emits binary wire decode for a struct, reading fields in contract order.
pub fn appendWireReadStruct(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    struct_name: []const u8,
    result_var: []const u8,
    structs: []const api.UserStruct,
) std.mem.Allocator.Error!void {
    const s = findStruct(structs, struct_name) orelse return;
    for (s.fields) |field| {
        try appendWireReadField(out, arena, field, structs);
    }
    try helpers.appendFmt(out, arena, "    const {s} = {s}{{ ", .{ result_var, struct_name });
    for (s.fields, 0..) |field, i| {
        if (i > 0) try out.appendSlice(arena, ", ");
        try helpers.appendFmt(out, arena, ".{s} = wire_{s}", .{ field.name, field.name });
    }
    try out.appendSlice(arena, " };\n");
}

/// Emits a single wire read call for a struct field.
fn appendWireReadField(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    field: api.StructField,
    structs: []const api.UserStruct,
) std.mem.Allocator.Error!void {
    const err_tail = " catch return setLastError(.argument, statusCode(.invalid_argument), \"invalid binary input\");\n";
    switch (field.field_type) {
        .string => try helpers.appendFmt(out, arena, "    const wire_{s} = wireReadString(input_bytes, &wire_off){s}", .{ field.name, err_tail }),
        .int => try helpers.appendFmt(out, arena, "    const wire_{s} = wireReadI64(input_bytes, &wire_off){s}", .{ field.name, err_tail }),
        .bool => try helpers.appendFmt(out, arena, "    const wire_{s} = wireReadBool(input_bytes, &wire_off){s}", .{ field.name, err_tail }),
        .user_enum => |enum_name| {
            try helpers.appendFmt(out, arena, "    const wire_{s}_raw = wireReadI64(input_bytes, &wire_off){s}", .{ field.name, err_tail });
            try helpers.appendFmt(
                out,
                arena,
                "    const wire_{s} = std.enums.fromInt({s}, @as(i64, wire_{s}_raw)) orelse return setLastError(.argument, statusCode(.invalid_argument), \"invalid enum ordinal\");\n",
                .{ field.name, enum_name, field.name },
            );
        },
        .user_struct => |nested_name| {
            try appendWireReadStruct(out, arena, nested_name, try std.fmt.allocPrint(arena, "wire_{s}", .{field.name}), structs);
        },
        .void => {},
    }
}

/// Emits binary wire encoding for a struct output value.
pub fn appendStructBinaryEncode(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    struct_name: []const u8,
    structs: []const api.UserStruct,
) !void {
    try out.appendSlice(arena, "    var wire_buf = std.ArrayList(u8).empty;\n");
    const s = findStruct(structs, struct_name) orelse return;
    for (s.fields) |field| {
        try appendWireWriteField(out, arena, field, "value", structs);
    }
    try out.appendSlice(arena, "    const owned = wire_buf.toOwnedSlice(ffi_output_allocator) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
}

/// Emits a single wire write call for a struct field.
fn appendWireWriteField(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    field: api.StructField,
    value_expr: []const u8,
    structs: []const api.UserStruct,
) !void {
    const oom = " catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n";
    switch (field.field_type) {
        .string => try helpers.appendFmt(out, arena, "    wireWriteString(&wire_buf, ffi_output_allocator, {s}.{s}){s}", .{ value_expr, field.name, oom }),
        .int => try helpers.appendFmt(out, arena, "    wireWriteI64(&wire_buf, ffi_output_allocator, {s}.{s}){s}", .{ value_expr, field.name, oom }),
        .bool => try helpers.appendFmt(out, arena, "    wireWriteBool(&wire_buf, ffi_output_allocator, {s}.{s}){s}", .{ value_expr, field.name, oom }),
        .user_enum => try helpers.appendFmt(out, arena, "    wireWriteI64(&wire_buf, ffi_output_allocator, @intFromEnum({s}.{s})){s}", .{ value_expr, field.name, oom }),
        .user_struct => |nested_name| {
            const nested_s = findStruct(structs, nested_name) orelse return;
            const nested_expr = try std.fmt.allocPrint(arena, "{s}.{s}", .{ value_expr, field.name });
            for (nested_s.fields) |nested_field| {
                try appendWireWriteField(out, arena, nested_field, nested_expr, structs);
            }
        },
        .void => {},
    }
}
