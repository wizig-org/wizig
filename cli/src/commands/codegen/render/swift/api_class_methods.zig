//! Swift API method and event emitter renderer.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

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

        if (method.output == .string) {
            switch (method.input) {
                .void => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try helpers.appendFmt(out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(outPtr, outLen)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .string => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
                    try helpers.appendFmt(out, arena, "            try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{symbol_name});
                    try out.appendSlice(arena, "                fn(inputPtr, inputLen, outPtr, outLen)\n");
                    try out.appendSlice(arena, "            }\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .int => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (Int64, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try helpers.appendFmt(out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(input, outPtr, outLen)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .bool => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UInt8, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
                    try helpers.appendFmt(out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(inputFlag, outPtr, outLen)\n");
                    try out.appendSlice(arena, "        }\n");
                },
            }
        } else if (method.output == .int) {
            switch (method.input) {
                .void => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafeMutablePointer<Int64>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try helpers.appendFmt(out, arena, "        return try callIntOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .string => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Int64>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
                    try helpers.appendFmt(out, arena, "            try callIntOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "                fn(inputPtr, inputLen, outValue)\n");
                    try out.appendSlice(arena, "            }\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .int => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (Int64, UnsafeMutablePointer<Int64>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try helpers.appendFmt(out, arena, "        return try callIntOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(input, outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .bool => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UInt8, UnsafeMutablePointer<Int64>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
                    try helpers.appendFmt(out, arena, "        return try callIntOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(inputFlag, outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
            }
        } else if (method.output == .bool) {
            switch (method.input) {
                .void => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try helpers.appendFmt(out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .string => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UInt8>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
                    try helpers.appendFmt(out, arena, "            try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "                fn(inputPtr, inputLen, outValue)\n");
                    try out.appendSlice(arena, "            }\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .int => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (Int64, UnsafeMutablePointer<UInt8>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try helpers.appendFmt(out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(input, outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .bool => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UInt8, UnsafeMutablePointer<UInt8>?) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
                    try helpers.appendFmt(out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(inputFlag, outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
            }
        } else {
            switch (method.input) {
                .void => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) () -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn()\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .string => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafePointer<UInt8>, Int) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        try withUTF8Pointer(input) { inputPtr, inputLen in\n");
                    try helpers.appendFmt(out, arena, "            try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                    try out.appendSlice(arena, "                fn(inputPtr, inputLen)\n");
                    try out.appendSlice(arena, "            }\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .int => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (Int64) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(input)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .bool => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UInt8) -> Int32\n");
                    try helpers.appendFmt(out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
                    try helpers.appendFmt(out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(inputFlag)\n");
                    try out.appendSlice(arena, "        }\n");
                },
            }
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
