//! Optional Zig API contract overrides for Wizig codegen.
//!
//! Discovery from `lib/**/*.zig` works without this file.
//! Edit this file only when you need explicit method/event declarations.
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
