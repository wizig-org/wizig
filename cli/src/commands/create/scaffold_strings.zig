//! String and identifier normalization utilities for scaffolding.
//!
//! The functions in this file convert user-provided project names into stable
//! forms suitable for file paths, package identifiers, and generated type names.
const std = @import("std");

/// Produces a filesystem-safe project name.
///
/// Allowed characters are ASCII alphanumerics plus `-` and `_`.
/// Spaces are normalized to `-`; all other characters are dropped.
pub fn sanitizeProjectName(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (raw_name) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_') {
            try out.append(allocator, ch);
        } else if (ch == ' ') {
            try out.append(allocator, '-');
        }
    }

    const value = try out.toOwnedSlice(allocator);
    if (value.len == 0) return error.CreateFailed;
    return value;
}

/// Converts a project name into a lowercase identifier token.
///
/// This output is used for app identifiers and token substitutions where
/// punctuation must be removed and the result cannot start with a digit.
pub fn toIdentifierLower(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (raw_name) |ch| {
        if (std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch)) {
            try out.append(allocator, std.ascii.toLower(ch));
        }
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "app");
    }

    if (std.ascii.isDigit(out.items[0])) {
        try out.insertSlice(allocator, 0, "app");
    }

    return out.toOwnedSlice(allocator);
}

/// Converts a project name into a Java/Kotlin package segment.
///
/// Segment output is lowercase and uses single underscores as separators.
/// Leading digits are guarded by prefixing `app_`.
pub fn sanitizePackageSegment(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (raw_name) |ch| {
        if (std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch)) {
            try out.append(allocator, std.ascii.toLower(ch));
        } else if (ch == '-' or ch == '_' or ch == ' ') {
            if (out.items.len == 0 or out.items[out.items.len - 1] == '_') continue;
            try out.append(allocator, '_');
        }
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "app");
    }

    if (std.ascii.isDigit(out.items[0])) {
        try out.insertSlice(allocator, 0, "app_");
    }

    return out.toOwnedSlice(allocator);
}

/// Converts a dot-delimited package name to an OS-native path.
pub fn packageNameToPath(allocator: std.mem.Allocator, package_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (package_name) |ch| {
        if (ch == '.') {
            try out.append(allocator, std.fs.path.sep);
            continue;
        }
        try out.append(allocator, ch);
    }

    return out.toOwnedSlice(allocator);
}

/// Normalizes any path separators to forward slashes.
///
/// Template placeholder path segments use `/` regardless of host OS.
pub fn toForwardSlashes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, input);
    for (out) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
    return out;
}

/// Escapes values written into Gradle `local.properties` files.
///
/// Backslashes must be doubled to survive Java properties parsing.
pub fn escapeLocalPropertiesValue(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (input) |ch| {
        if (ch == '\\') {
            try out.appendSlice(allocator, "\\\\");
            continue;
        }
        try out.append(allocator, ch);
    }
    return out.toOwnedSlice(allocator);
}

/// Converts arbitrary project names to Swift type identifiers.
///
/// Word boundaries are inferred from non-alphanumeric separators and words are
/// title-cased. If the first emitted character would be a digit, `A` is added.
pub fn toSwiftTypeName(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var uppercase_next = true;
    for (raw_name) |ch| {
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch))) {
            uppercase_next = true;
            continue;
        }

        if (out.items.len == 0 and std.ascii.isDigit(ch)) {
            try out.append(allocator, 'A');
        }

        if (uppercase_next and std.ascii.isAlphabetic(ch)) {
            try out.append(allocator, std.ascii.toUpper(ch));
        } else {
            try out.append(allocator, ch);
        }
        uppercase_next = false;
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "WizigApp");
    }

    return out.toOwnedSlice(allocator);
}

test "sanitizeProjectName keeps safe characters" {
    const got = try sanitizeProjectName(std.testing.allocator, "My App!@# 123");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("My-App-123", got);
}

test "sanitizePackageSegment produces valid lowercase token" {
    const got = try sanitizePackageSegment(std.testing.allocator, "123 Hello-World");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("app_123_hello_world", got);
}

test "packageNameToPath converts dots to separators" {
    const got = try packageNameToPath(std.testing.allocator, "dev.wizig.demo");
    defer std.testing.allocator.free(got);
    try std.testing.expect(std.mem.indexOfScalar(u8, got, '.') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, got, std.fs.path.sep) != null);
}

test "toSwiftTypeName strips separators and capitalizes words" {
    const got = try toSwiftTypeName(std.testing.allocator, "my-cool_app");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("MyCoolApp", got);
}

test "escapeLocalPropertiesValue escapes backslashes" {
    const got = try escapeLocalPropertiesValue(std.testing.allocator, "C:\\Users\\wizig\\sdk");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("C:\\\\Users\\\\wizig\\\\sdk", got);
}
