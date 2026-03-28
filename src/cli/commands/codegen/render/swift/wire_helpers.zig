//! Emits `WizigWireReader` and `WizigWireWriter` private structs for binary
//! wire format v1 encoding/decoding of user-defined struct types.
//!
//! Wire format v1 layout:
//!   string:  [u32 length LE][bytes...]
//!   int:     [i64 value LE] (8 bytes)
//!   bool:    [u8 value] (0 or 1)
//!   enum:    [i64 rawValue LE]
//!   struct:  [field1][field2]... (fields in contract order)

const std = @import("std");

/// Appends the `WizigWireReader` and `WizigWireWriter` Swift struct
/// definitions to the output buffer.
pub fn appendWireHelpers(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try appendWireReader(out, arena);
    try appendWireWriter(out, arena);
}

/// Emits the `WizigWireReader` struct for decoding binary wire data.
fn appendWireReader(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "private struct WizigWireReader {\n");
    try out.appendSlice(arena, "    let ptr: UnsafeRawPointer\n");
    try out.appendSlice(arena, "    let len: Int\n");
    try out.appendSlice(arena, "    var offset: Int = 0\n\n");

    try out.appendSlice(arena, "    mutating func readU32() throws -> UInt32 {\n");
    try out.appendSlice(arena, "        guard offset + 4 <= len else { throw WizigGeneratedApiError.invalidBinaryData(function: \"wire\") }\n");
    try out.appendSlice(arena, "        let val = ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)\n");
    try out.appendSlice(arena, "        offset += 4\n");
    try out.appendSlice(arena, "        return UInt32(littleEndian: val)\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    mutating func readI64() throws -> Int64 {\n");
    try out.appendSlice(arena, "        guard offset + 8 <= len else { throw WizigGeneratedApiError.invalidBinaryData(function: \"wire\") }\n");
    try out.appendSlice(arena, "        let val = ptr.loadUnaligned(fromByteOffset: offset, as: Int64.self)\n");
    try out.appendSlice(arena, "        offset += 8\n");
    try out.appendSlice(arena, "        return Int64(littleEndian: val)\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    mutating func readBool() throws -> Bool {\n");
    try out.appendSlice(arena, "        guard offset + 1 <= len else { throw WizigGeneratedApiError.invalidBinaryData(function: \"wire\") }\n");
    try out.appendSlice(arena, "        let val = ptr.load(fromByteOffset: offset, as: UInt8.self)\n");
    try out.appendSlice(arena, "        offset += 1\n");
    try out.appendSlice(arena, "        return val != 0\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    mutating func readString() throws -> String {\n");
    try out.appendSlice(arena, "        let strLen = Int(try readU32())\n");
    try out.appendSlice(arena, "        guard offset + strLen <= len else { throw WizigGeneratedApiError.invalidBinaryData(function: \"wire\") }\n");
    try out.appendSlice(arena,
        \\        let str = String(decoding: UnsafeBufferPointer(
        \\            start: ptr.assumingMemoryBound(to: UInt8.self).advanced(by: offset),
        \\            count: strLen), as: UTF8.self)
        \\
    );
    try out.appendSlice(arena, "        offset += strLen\n");
    try out.appendSlice(arena, "        return str\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "}\n\n");
}

/// Emits the `WizigWireWriter` struct for encoding binary wire data.
fn appendWireWriter(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "private struct WizigWireWriter {\n");
    try out.appendSlice(arena, "    var bytes: [UInt8] = []\n\n");

    try out.appendSlice(arena, "    mutating func writeU32(_ val: UInt32) {\n");
    try out.appendSlice(arena, "        var le = val.littleEndian\n");
    try out.appendSlice(arena, "        withUnsafeBytes(of: &le) { bytes.append(contentsOf: $0) }\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    mutating func writeI64(_ val: Int64) {\n");
    try out.appendSlice(arena, "        var le = val.littleEndian\n");
    try out.appendSlice(arena, "        withUnsafeBytes(of: &le) { bytes.append(contentsOf: $0) }\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    mutating func writeBool(_ val: Bool) {\n");
    try out.appendSlice(arena, "        bytes.append(val ? 1 : 0)\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    mutating func writeString(_ val: String) {\n");
    try out.appendSlice(arena, "        writeU32(UInt32(val.utf8.count))\n");
    try out.appendSlice(arena, "        bytes.append(contentsOf: val.utf8)\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "}\n\n");
}
