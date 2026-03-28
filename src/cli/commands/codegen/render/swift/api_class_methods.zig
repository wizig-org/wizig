//! Swift API method and event emitter renderer.
//!
//! Methods call C exports through the static `WizigFFI` import. User structs and
//! enums are translated to wire representations automatically:
//! - structs -> JSON string wire
//! - enums   -> Int64 raw value wire

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

/// Appends generated API methods plus sink event forwarding methods.
pub fn appendApiClassMethods(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
) !void {
    for (spec.methods) |method| {
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

        const input_wire = helpers.wireKind(method.input);
        const output_wire = helpers.wireKind(method.output);
        const input_is_user_struct = switch (method.input) {
            .user_struct => true,
            else => false,
        };
        const input_is_user_enum = switch (method.input) {
            .user_enum => true,
            else => false,
        };
        const output_is_user_struct = switch (method.output) {
            .user_struct => true,
            else => false,
        };
        const output_is_user_enum = switch (method.output) {
            .user_enum => true,
            else => false,
        };

        if (input_is_user_struct) {
            try helpers.appendFmt(out, arena, "        let encodedInput = try encodeStructInput(input, function: \"{s}\")\n", .{symbol_name});
        } else if (input_is_user_enum) {
            try out.appendSlice(arena, "        let enumRawInput = input.rawValue\n");
        } else if (input_wire == .bool) {
            try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
        }

        switch (output_wire) {
            .string => {
                const call_name = if (output_is_user_struct) "callStructOutput" else "callStringOutput";
                switch (input_wire) {
                    .void => {
                        try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ outPtr, outLen in\n", .{ call_name, symbol_name });
                        try helpers.appendFmt(out, arena, "            {s}(outPtr, outLen)\n", .{symbol_name});
                        try out.appendSlice(arena, "        }\n");
                    },
                    .string => {
                        const source = if (input_is_user_struct) "encodedInput" else "input";
                        try helpers.appendFmt(out, arena, "        return try withUTF8Pointer({s}) {{ inputPtr, inputLen in\n", .{source});
                        try helpers.appendFmt(out, arena, "            try {s}(function: \"{s}\") {{ outPtr, outLen in\n", .{ call_name, symbol_name });
                        try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, outPtr, outLen)\n", .{symbol_name});
                        try out.appendSlice(arena, "            }\n");
                        try out.appendSlice(arena, "        }\n");
                    },
                    .int => {
                        const arg = if (input_is_user_enum) "enumRawInput" else "input";
                        try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ outPtr, outLen in\n", .{ call_name, symbol_name });
                        try helpers.appendFmt(out, arena, "            {s}({s}, outPtr, outLen)\n", .{ symbol_name, arg });
                        try out.appendSlice(arena, "        }\n");
                    },
                    .bool => {
                        try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ outPtr, outLen in\n", .{ call_name, symbol_name });
                        try helpers.appendFmt(out, arena, "            {s}(inputFlag, outPtr, outLen)\n", .{symbol_name});
                        try out.appendSlice(arena, "        }\n");
                    },
                }
            },
            .int => {
                const call_name = if (output_is_user_enum) "callEnumOutput" else "callIntOutput";
                switch (input_wire) {
                    .void => {
                        try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ outValue in\n", .{ call_name, symbol_name });
                        try helpers.appendFmt(out, arena, "            {s}(outValue)\n", .{symbol_name});
                        try out.appendSlice(arena, "        }\n");
                    },
                    .string => {
                        const source = if (input_is_user_struct) "encodedInput" else "input";
                        try helpers.appendFmt(out, arena, "        return try withUTF8Pointer({s}) {{ inputPtr, inputLen in\n", .{source});
                        try helpers.appendFmt(out, arena, "            try {s}(function: \"{s}\") {{ outValue in\n", .{ call_name, symbol_name });
                        try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, outValue)\n", .{symbol_name});
                        try out.appendSlice(arena, "            }\n");
                        try out.appendSlice(arena, "        }\n");
                    },
                    .int => {
                        const arg = if (input_is_user_enum) "enumRawInput" else "input";
                        try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ outValue in\n", .{ call_name, symbol_name });
                        try helpers.appendFmt(out, arena, "            {s}({s}, outValue)\n", .{ symbol_name, arg });
                        try out.appendSlice(arena, "        }\n");
                    },
                    .bool => {
                        try helpers.appendFmt(out, arena, "        return try {s}(function: \"{s}\") {{ outValue in\n", .{ call_name, symbol_name });
                        try helpers.appendFmt(out, arena, "            {s}(inputFlag, outValue)\n", .{symbol_name});
                        try out.appendSlice(arena, "        }\n");
                    },
                }
            },
            .bool => {
                switch (input_wire) {
                    .void => {
                        try helpers.appendFmt(out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                        try helpers.appendFmt(out, arena, "            {s}(outValue)\n", .{symbol_name});
                        try out.appendSlice(arena, "        }\n");
                    },
                    .string => {
                        const source = if (input_is_user_struct) "encodedInput" else "input";
                        try helpers.appendFmt(out, arena, "        return try withUTF8Pointer({s}) {{ inputPtr, inputLen in\n", .{source});
                        try helpers.appendFmt(out, arena, "            try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                        try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen, outValue)\n", .{symbol_name});
                        try out.appendSlice(arena, "            }\n");
                        try out.appendSlice(arena, "        }\n");
                    },
                    .int => {
                        const arg = if (input_is_user_enum) "enumRawInput" else "input";
                        try helpers.appendFmt(out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                        try helpers.appendFmt(out, arena, "            {s}({s}, outValue)\n", .{ symbol_name, arg });
                        try out.appendSlice(arena, "        }\n");
                    },
                    .bool => {
                        try helpers.appendFmt(out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                        try helpers.appendFmt(out, arena, "            {s}(inputFlag, outValue)\n", .{symbol_name});
                        try out.appendSlice(arena, "        }\n");
                    },
                }
            },
            .void => {
                switch (input_wire) {
                    .void => {
                        try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                        try helpers.appendFmt(out, arena, "            {s}()\n", .{symbol_name});
                        try out.appendSlice(arena, "        }\n");
                    },
                    .string => {
                        const source = if (input_is_user_struct) "encodedInput" else "input";
                        try helpers.appendFmt(out, arena, "        try withUTF8Pointer({s}) {{ inputPtr, inputLen in\n", .{source});
                        try helpers.appendFmt(out, arena, "            try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                        try helpers.appendFmt(out, arena, "                {s}(inputPtr, inputLen)\n", .{symbol_name});
                        try out.appendSlice(arena, "            }\n");
                        try out.appendSlice(arena, "        }\n");
                    },
                    .int => {
                        const arg = if (input_is_user_enum) "enumRawInput" else "input";
                        try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                        try helpers.appendFmt(out, arena, "            {s}({s})\n", .{ symbol_name, arg });
                        try out.appendSlice(arena, "        }\n");
                    },
                    .bool => {
                        try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                        try helpers.appendFmt(out, arena, "            {s}(inputFlag)\n", .{symbol_name});
                        try out.appendSlice(arena, "        }\n");
                    },
                }
            },
        }

        try out.appendSlice(arena, "    }\n\n");
    }

    for (spec.events) |event| {
        const event_name = try helpers.upperCamel(arena, event.name);
        try helpers.appendFmt(out, arena, "    public func emit{s}(payload: {s}) {{\n", .{ event_name, helpers.swiftType(event.payload) });
        try helpers.appendFmt(out, arena, "        sink?.on{s}(payload: payload)\n", .{event_name});
        try out.appendSlice(arena, "    }\n\n");
    }

    try out.appendSlice(arena, "}\n");
}
