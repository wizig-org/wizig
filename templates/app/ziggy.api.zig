//! Zig-first API contract for Ziggy codegen.
//!
//! Edit this file to define the typed host <-> Zig surface.
//! Supported scalar tags today: `.string`, `.int`, `.bool`, `.void`.

/// Logical namespace used by generated bindings.
pub const namespace = "{{APP_IDENTIFIER}}";

/// Host-callable methods (host -> Zig).
pub const methods = .{
    .{ .name = "echo", .input = .string, .output = .string },
};

/// Zig-emitted events (Zig -> host).
pub const events = .{
    .{ .name = "log", .payload = .string },
};
