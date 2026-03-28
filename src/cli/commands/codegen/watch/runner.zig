//! Long-running watch loop for incremental code generation.
//!
//! ## Responsibilities
//! - Poll source/contract state on a fixed interval.
//! - Trigger codegen only when the watch fingerprint changes.
//! - Keep running on recoverable errors so IDE editing remains smooth.
//!
//! ## Integration Model
//! The runner receives callback functions for:
//! - resolving the active API contract path
//! - executing code generation
//!
//! This keeps the watch loop decoupled from `codegen/root.zig` internals.
const std = @import("std");
const Io = std.Io;

const fingerprint = @import("fingerprint.zig");

/// Callback used to resolve the currently active contract path.
///
/// The callback should return:
/// - `null` when discovery mode is active
/// - non-null absolute path when a contract is active
pub const ResolveApiPathFn = *const fn (
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) anyerror!?[]const u8;

/// Callback used to execute a single codegen pass.
pub const GenerateProjectFn = *const fn (
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) anyerror!void;

/// Runs the incremental watch loop until externally interrupted.
///
/// Behavior summary:
/// - Initial pass runs immediately.
/// - Subsequent passes run only on fingerprint changes.
/// - On generation failure, the loop waits for another change.
pub fn runWatchCodegenLoop(
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
    watch_interval_ms: u64,
    resolve_api_path_fn: ResolveApiPathFn,
    generate_project_fn: GenerateProjectFn,
) !void {
    try stdout.print(
        "watching codegen inputs under '{s}' (interval: {d}ms, Ctrl+C to stop)\n",
        .{ project_root, watch_interval_ms },
    );
    try stdout.flush();

    var watch_arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer watch_arena_state.deinit();

    var last_fingerprint: ?[32]u8 = null;
    while (true) {
        _ = watch_arena_state.reset(.retain_capacity);
        const watch_arena = watch_arena_state.allocator();

        const api_path = resolve_api_path_fn(watch_arena, io, stderr, project_root, api_override) catch |err| {
            try stderr.print("watch: failed to resolve API contract: {s}\n", .{@errorName(err)});
            try stderr.flush();
            sleepWatchInterval(io, watch_interval_ms);
            continue;
        };
        const current_fingerprint = try fingerprint.computeWatchFingerprint(watch_arena, io, project_root, api_path);

        const should_generate = if (last_fingerprint) |previous|
            !std.mem.eql(u8, &previous, &current_fingerprint)
        else
            true;
        if (!should_generate) {
            sleepWatchInterval(io, watch_interval_ms);
            continue;
        }

        try stdout.writeAll("change detected; running codegen...\n");
        try stdout.flush();

        generate_project_fn(watch_arena, io, stderr, stdout, project_root, api_path) catch |err| {
            try stderr.print("watch: codegen failed ({s}); waiting for next change\n", .{@errorName(err)});
            try stderr.flush();

            // Preserve the failed fingerprint to avoid immediate hot-loop retries.
            last_fingerprint = current_fingerprint;
            sleepWatchInterval(io, watch_interval_ms);
            continue;
        };

        const refreshed_api_path = resolve_api_path_fn(watch_arena, io, stderr, project_root, api_override) catch api_path;
        last_fingerprint = try fingerprint.computeWatchFingerprint(watch_arena, io, project_root, refreshed_api_path);
        sleepWatchInterval(io, watch_interval_ms);
    }
}

/// Sleeps for the configured watch polling interval.
fn sleepWatchInterval(io: std.Io, watch_interval_ms: u64) void {
    const ns = std.math.mul(u64, watch_interval_ms, std.time.ns_per_ms) catch std.math.maxInt(u64);
    const duration = std.Io.Duration.fromNanoseconds(@as(i96, @intCast(ns)));
    std.Io.sleep(io, duration, .awake) catch {};
}
