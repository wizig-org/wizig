//! Source classification helpers for `wizig plugin add`.
const std = @import("std");

/// Returns true for source strings that look like git remotes.
pub fn isLikelyGitSource(source: []const u8) bool {
    return std.mem.startsWith(u8, source, "https://") or
        std.mem.startsWith(u8, source, "git@") or
        std.mem.endsWith(u8, source, ".git");
}

/// Derives a destination directory name from a git source or filesystem path.
pub fn repoNameFromSource(source: []const u8) []const u8 {
    const base = std.fs.path.basename(source);
    if (std.mem.endsWith(u8, base, ".git") and base.len > 4) {
        return base[0 .. base.len - 4];
    }
    return base;
}

test "isLikelyGitSource recognizes common git forms" {
    try std.testing.expect(isLikelyGitSource("https://example.com/repo.git"));
    try std.testing.expect(isLikelyGitSource("git@example.com:repo.git"));
    try std.testing.expect(isLikelyGitSource("repo.git"));
    try std.testing.expect(!isLikelyGitSource("/Users/me/repo"));
}

test "repoNameFromSource strips trailing .git from basename only" {
    try std.testing.expectEqualStrings("repo", repoNameFromSource("https://example.com/repo.git"));
    try std.testing.expectEqualStrings("repo", repoNameFromSource("/tmp/repo"));
    try std.testing.expectEqualStrings("repo.git", repoNameFromSource("/tmp/nested/repo.gitkeep"));
}
