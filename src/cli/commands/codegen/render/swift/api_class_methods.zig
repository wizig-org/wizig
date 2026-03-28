//! Swift API method and event emitter renderer.
//!
//! Methods call C exports through the static `WizigFFI` import. User structs
//! and enums are translated to wire representations automatically:
//! - structs -> binary wire format v1 (field concatenation)
//! - enums   -> Int64 raw value wire

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");
const api_method_binary = @import("api_method_binary.zig");
const api_method_scalar = @import("api_method_scalar.zig");

/// Appends generated API methods plus sink event forwarding methods.
pub fn appendApiClassMethods(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
) !void {
    for (spec.methods) |method| {
        try appendMethod(out, arena, method);
    }
    for (spec.events) |event| {
        try appendEventEmitter(out, arena, event);
    }
    try out.appendSlice(arena, "}\n");
}

/// Emits a single public API method with appropriate input/output handling.
fn appendMethod(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    method: api.ApiMethod,
) !void {
    const symbol_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});
    const params = if (method.input == .void)
        "()"
    else
        try std.fmt.allocPrint(arena, "(_ input: {s})", .{helpers.swiftType(method.input)});

    if (method.output == .void) {
        try helpers.appendFmt(out, arena, "    public func {s}{s} throws {{\n", .{ method.name, params });
    } else {
        try helpers.appendFmt(out, arena, "    public func {s}{s} throws -> {s} {{\n", .{ method.name, params, helpers.swiftType(method.output) });
    }

    try appendMethodBody(out, arena, method, symbol_name);
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits the method body: input preparation + output call wrapper.
fn appendMethodBody(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    method: api.ApiMethod,
    symbol_name: []const u8,
) !void {
    const input_wire = helpers.wireKind(method.input);
    const input_is_user_struct = method.input == .user_struct;
    const input_is_user_enum = method.input == .user_enum;
    const output_is_user_struct = method.output == .user_struct;
    const output_is_user_enum = method.output == .user_enum;

    // Prepare input conversions.
    if (input_is_user_struct) {
        try helpers.appendFmt(out, arena, "        let binaryInput = input.toBinary()\n", .{});
    } else if (input_is_user_enum) {
        try out.appendSlice(arena, "        let enumRawInput = input.rawValue\n");
    } else if (input_wire == .bool) {
        try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
    }

    // Emit output call with input wiring.
    if (output_is_user_struct) {
        try api_method_binary.appendBinaryOutputCall(out, arena, method, symbol_name, input_wire, input_is_user_struct, input_is_user_enum);
    } else {
        try api_method_scalar.appendScalarOutputCall(out, arena, method, symbol_name, input_wire, input_is_user_struct, input_is_user_enum, output_is_user_enum);
    }
}

/// Emits a single event forwarding method.
fn appendEventEmitter(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    event: api.ApiEvent,
) !void {
    const event_name = try helpers.upperCamel(arena, event.name);
    try helpers.appendFmt(out, arena, "    public func emit{s}(payload: {s}) {{\n", .{ event_name, helpers.swiftType(event.payload) });
    try helpers.appendFmt(out, arena, "        sink?.on{s}(payload: payload)\n", .{event_name});
    try out.appendSlice(arena, "    }\n\n");
}
