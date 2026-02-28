//! Plugin manifest v2 schema parsing/validation.
const std = @import("std");

/// Swift Package Manager dependency descriptor declared by a plugin.
pub const SpmDependency = struct {
    url: []u8,
    requirement: []u8,
    product: []u8,

    /// Releases owned string fields.
    pub fn deinit(self: *SpmDependency, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.requirement);
        allocator.free(self.product);
        self.* = undefined;
    }
};

/// Maven dependency descriptor declared by a plugin.
pub const MavenDependency = struct {
    coordinate: []u8,
    classifier: []u8,
    scope: []u8,

    /// Releases owned string fields.
    pub fn deinit(self: *MavenDependency, allocator: std.mem.Allocator) void {
        allocator.free(self.coordinate);
        allocator.free(self.classifier);
        allocator.free(self.scope);
        self.* = undefined;
    }
};

/// Parsed plugin manifest with native dependency descriptors.
pub const PluginManifest = struct {
    schema_version: u32,
    id: []u8,
    version: []u8,
    api_version: u32,
    capabilities: [][]u8,
    ios_spm: []SpmDependency,
    android_maven: []MavenDependency,

    /// Parses a JSON plugin manifest payload into a validated structure.
    pub fn parse(allocator: std.mem.Allocator, text: []const u8) !PluginManifest {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch {
            return error.InvalidManifest;
        };
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidManifest;
        const root = parsed.value.object;

        const schema_version = try parseU32(root, "schema_version");
        if (schema_version != 2) return error.UnsupportedSchema;

        const id = try dupStringField(allocator, root, "id");
        errdefer allocator.free(id);

        const version = try dupStringField(allocator, root, "version");
        errdefer allocator.free(version);

        const api_version = try parseU32(root, "api_version");

        const capabilities = try parseStringArray(allocator, root, "capabilities");
        errdefer freeStringSlice(allocator, capabilities);

        const ios_spm = try parseSpmDeps(allocator, root, "ios_spm");
        errdefer freeSpmSlice(allocator, ios_spm);

        const android_maven = try parseMavenDeps(allocator, root, "android_maven");
        errdefer freeMavenSlice(allocator, android_maven);

        return .{
            .schema_version = schema_version,
            .id = id,
            .version = version,
            .api_version = api_version,
            .capabilities = capabilities,
            .ios_spm = ios_spm,
            .android_maven = android_maven,
        };
    }

    /// Releases all manifest-owned memory.
    pub fn deinit(self: *PluginManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.version);
        freeStringSlice(allocator, self.capabilities);
        freeSpmSlice(allocator, self.ios_spm);
        freeMavenSlice(allocator, self.android_maven);
        self.* = undefined;
    }
};

fn parseU32(root: std.json.ObjectMap, field: []const u8) !u32 {
    const value = root.get(field) orelse return error.InvalidManifest;
    switch (value) {
        .integer => |v| {
            if (v < 0) return error.InvalidManifest;
            return std.math.cast(u32, v) orelse return error.InvalidManifest;
        },
        else => return error.InvalidManifest,
    }
}

fn dupStringField(
    allocator: std.mem.Allocator,
    root: std.json.ObjectMap,
    field: []const u8,
) ![]u8 {
    const value = root.get(field) orelse return error.InvalidManifest;
    if (value != .string) return error.InvalidManifest;
    if (value.string.len == 0) return error.InvalidManifest;
    return allocator.dupe(u8, value.string);
}

fn parseStringArray(
    allocator: std.mem.Allocator,
    root: std.json.ObjectMap,
    field: []const u8,
) ![][]u8 {
    const value = root.get(field) orelse return error.InvalidManifest;
    if (value != .array) return error.InvalidManifest;

    var out = std.ArrayList([]u8).empty;
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit(allocator);
    }

    for (value.array.items) |item| {
        if (item != .string) return error.InvalidManifest;
        try out.append(allocator, try allocator.dupe(u8, item.string));
    }

    return out.toOwnedSlice(allocator);
}

fn parseSpmDeps(
    allocator: std.mem.Allocator,
    root: std.json.ObjectMap,
    field: []const u8,
) ![]SpmDependency {
    const value = root.get(field) orelse return error.InvalidManifest;
    if (value != .array) return error.InvalidManifest;

    var out = std.ArrayList(SpmDependency).empty;
    errdefer {
        for (out.items) |*item| item.deinit(allocator);
        out.deinit(allocator);
    }

    for (value.array.items) |item| {
        if (item != .object) return error.InvalidManifest;
        const obj = item.object;
        const url = try dupStringField(allocator, obj, "url");
        errdefer allocator.free(url);
        const requirement = try dupStringField(allocator, obj, "requirement");
        errdefer allocator.free(requirement);
        const product = try dupStringField(allocator, obj, "product");
        errdefer allocator.free(product);

        try out.append(allocator, .{
            .url = url,
            .requirement = requirement,
            .product = product,
        });
    }

    return out.toOwnedSlice(allocator);
}

fn parseMavenDeps(
    allocator: std.mem.Allocator,
    root: std.json.ObjectMap,
    field: []const u8,
) ![]MavenDependency {
    const value = root.get(field) orelse return error.InvalidManifest;
    if (value != .array) return error.InvalidManifest;

    var out = std.ArrayList(MavenDependency).empty;
    errdefer {
        for (out.items) |*item| item.deinit(allocator);
        out.deinit(allocator);
    }

    for (value.array.items) |item| {
        if (item != .object) return error.InvalidManifest;
        const obj = item.object;

        const coordinate = try dupStringField(allocator, obj, "coordinate");
        errdefer allocator.free(coordinate);

        const classifier = if (obj.get("classifier")) |class_value| blk: {
            if (class_value != .string) return error.InvalidManifest;
            break :blk try allocator.dupe(u8, class_value.string);
        } else try allocator.dupe(u8, "");
        errdefer allocator.free(classifier);

        const scope = if (obj.get("scope")) |scope_value| blk: {
            if (scope_value != .string) return error.InvalidManifest;
            break :blk try allocator.dupe(u8, scope_value.string);
        } else try allocator.dupe(u8, "implementation");
        errdefer allocator.free(scope);

        try out.append(allocator, .{
            .coordinate = coordinate,
            .classifier = classifier,
            .scope = scope,
        });
    }

    return out.toOwnedSlice(allocator);
}

fn freeStringSlice(allocator: std.mem.Allocator, values: [][]u8) void {
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn freeSpmSlice(allocator: std.mem.Allocator, values: []SpmDependency) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}

fn freeMavenSlice(allocator: std.mem.Allocator, values: []MavenDependency) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}

test "parse manifest v2" {
    const text =
        \\{
        \\  "schema_version": 2,
        \\  "id": "dev.wizig.hello",
        \\  "version": "0.1.0",
        \\  "api_version": 1,
        \\  "capabilities": ["log"],
        \\  "ios_spm": [
        \\    {"url":"https://example.com/pkg.git","requirement":"from:1.0.0","product":"Pkg"}
        \\  ],
        \\  "android_maven": [
        \\    {"coordinate":"com.example:demo:1.0.0","classifier":"","scope":"implementation"}
        \\  ]
        \\}
    ;

    var manifest = try PluginManifest.parse(std.testing.allocator, text);
    defer manifest.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 2), manifest.schema_version);
    try std.testing.expectEqualStrings("dev.wizig.hello", manifest.id);
    try std.testing.expectEqual(@as(usize, 1), manifest.ios_spm.len);
    try std.testing.expectEqual(@as(usize, 1), manifest.android_maven.len);
    try std.testing.expectEqualStrings("Pkg", manifest.ios_spm[0].product);
    try std.testing.expectEqualStrings("implementation", manifest.android_maven[0].scope);
}
