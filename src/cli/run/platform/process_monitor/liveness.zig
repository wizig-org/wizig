//! Liveness-probe execution for monitored inherited processes.
const std = @import("std");

const spec = @import("spec.zig");
const term = @import("term.zig");

/// Runs the liveness probe and evaluates whether the app is still alive.
pub fn probeAppLiveness(io: std.Io, probe: spec.LivenessProbe) bool {
    var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    const result = std.process.run(scratch, io, .{
        .argv = probe.spec.argv,
        .cwd = spec.childCwd(probe.spec.cwd_path),
        .environ_map = probe.spec.environ_map,
        .stdout_limit = .limited(128 * 1024),
        .stderr_limit = .limited(128 * 1024),
    }) catch {
        return false;
    };
    return livenessProbeSatisfied(probe, result);
}

pub fn livenessProbeSatisfied(probe: spec.LivenessProbe, result: std.process.RunResult) bool {
    if (!term.termIsSuccess(result.term)) return false;
    if (probe.required_substring) |needle| {
        if (std.mem.indexOf(u8, result.stdout, needle) != null) return true;
        if (std.mem.indexOf(u8, result.stderr, needle) != null) return true;
        return false;
    }
    return true;
}

test "livenessProbeSatisfied accepts success without token requirement" {
    var stdout_text = [_]u8{ 'a', 'l', 'i', 'v', 'e' };
    const probe = spec.LivenessProbe{
        .spec = .{ .argv = &.{"echo"}, .label = "probe" },
    };
    const result: std.process.RunResult = .{
        .term = .{ .exited = 0 },
        .stdout = stdout_text[0..],
        .stderr = stdout_text[0..0],
    };
    try std.testing.expect(livenessProbeSatisfied(probe, result));
}

test "livenessProbeSatisfied requires substring when configured" {
    var stdout_ok = [_]u8{ 'h', 'a', 's', ' ', 't', 'o', 'k', 'e', 'n' };
    var stdout_missing = [_]u8{ 'n', 'o', 'p', 'e' };
    const probe = spec.LivenessProbe{
        .spec = .{ .argv = &.{"echo"}, .label = "probe" },
        .required_substring = "token",
    };
    const ok: std.process.RunResult = .{
        .term = .{ .exited = 0 },
        .stdout = stdout_ok[0..],
        .stderr = stdout_ok[0..0],
    };
    const missing: std.process.RunResult = .{
        .term = .{ .exited = 0 },
        .stdout = stdout_missing[0..],
        .stderr = stdout_missing[0..0],
    };
    try std.testing.expect(livenessProbeSatisfied(probe, ok));
    try std.testing.expect(!livenessProbeSatisfied(probe, missing));
}
