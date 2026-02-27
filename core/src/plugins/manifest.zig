const std = @import("std");

pub const PluginManifest = struct {
    id: []u8,
    version: []u8,
    api_version: u32,
    capabilities: [][]u8,
    ios_spm: [][]u8,
    android_maven: [][]u8,

    pub fn parse(allocator: std.mem.Allocator, text: []const u8) !PluginManifest {
        var id: ?[]u8 = null;
        var version: ?[]u8 = null;
        var api_version: ?u32 = null;
        var capabilities = std.ArrayList([]u8).empty;
        var ios_spm = std.ArrayList([]u8).empty;
        var android_maven = std.ArrayList([]u8).empty;

        errdefer {
            if (id) |value| allocator.free(value);
            if (version) |value| allocator.free(value);
            freeArrayListOwnedStrings(allocator, &capabilities);
            freeArrayListOwnedStrings(allocator, &ios_spm);
            freeArrayListOwnedStrings(allocator, &android_maven);
        }

        var lines = std.mem.tokenizeScalar(u8, text, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            const eq_index = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidAssignment;
            const key = std.mem.trim(u8, line[0..eq_index], " \t");
            const value = std.mem.trim(u8, line[eq_index + 1 ..], " \t");

            if (std.mem.eql(u8, key, "id")) {
                if (id != null) return error.DuplicateKey;
                id = try parseQuotedString(allocator, value);
                continue;
            }
            if (std.mem.eql(u8, key, "version")) {
                if (version != null) return error.DuplicateKey;
                version = try parseQuotedString(allocator, value);
                continue;
            }
            if (std.mem.eql(u8, key, "api_version")) {
                if (api_version != null) return error.DuplicateKey;
                api_version = try std.fmt.parseUnsigned(u32, value, 10);
                continue;
            }
            if (std.mem.eql(u8, key, "capabilities")) {
                try parseQuotedArray(allocator, value, &capabilities);
                continue;
            }
            if (std.mem.eql(u8, key, "ios_spm")) {
                try parseQuotedArray(allocator, value, &ios_spm);
                continue;
            }
            if (std.mem.eql(u8, key, "android_maven")) {
                try parseQuotedArray(allocator, value, &android_maven);
                continue;
            }

            return error.UnknownKey;
        }

        const capabilities_slice = try capabilities.toOwnedSlice(allocator);
        errdefer freeOwnedStringSlice(allocator, capabilities_slice);
        const ios_spm_slice = try ios_spm.toOwnedSlice(allocator);
        errdefer freeOwnedStringSlice(allocator, ios_spm_slice);
        const android_maven_slice = try android_maven.toOwnedSlice(allocator);
        errdefer freeOwnedStringSlice(allocator, android_maven_slice);

        return .{
            .id = id orelse return error.MissingId,
            .version = version orelse return error.MissingVersion,
            .api_version = api_version orelse return error.MissingApiVersion,
            .capabilities = capabilities_slice,
            .ios_spm = ios_spm_slice,
            .android_maven = android_maven_slice,
        };
    }

    pub fn deinit(self: *PluginManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.version);
        freeOwnedStringSlice(allocator, self.capabilities);
        freeOwnedStringSlice(allocator, self.ios_spm);
        freeOwnedStringSlice(allocator, self.android_maven);
        self.* = undefined;
    }
};

fn freeArrayListOwnedStrings(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |item| {
        allocator.free(item);
    }
    list.deinit(allocator);
}

fn freeOwnedStringSlice(allocator: std.mem.Allocator, values: [][]u8) void {
    for (values) |value| {
        allocator.free(value);
    }
    allocator.free(values);
}

fn parseQuotedString(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const parsed = try parseQuotedToken(allocator, value, 0);
    errdefer allocator.free(parsed.value);

    const rest = std.mem.trim(u8, value[parsed.next_index..], " \t");
    if (rest.len != 0) return error.InvalidQuotedString;

    return parsed.value;
}

const ParsedToken = struct {
    value: []u8,
    next_index: usize,
};

fn parseQuotedToken(allocator: std.mem.Allocator, input: []const u8, start_index: usize) !ParsedToken {
    if (start_index >= input.len or input[start_index] != '"') return error.InvalidQuotedString;

    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(allocator);

    var i = start_index + 1;
    while (i < input.len) : (i += 1) {
        const ch = input[i];

        if (ch == '"') {
            return .{
                .value = try buffer.toOwnedSlice(allocator),
                .next_index = i + 1,
            };
        }

        if (ch == '\\') {
            i += 1;
            if (i >= input.len) return error.InvalidEscapeSequence;

            const escaped: u8 = switch (input[i]) {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => return error.InvalidEscapeSequence,
            };
            try buffer.append(allocator, escaped);
            continue;
        }

        try buffer.append(allocator, ch);
    }

    return error.UnterminatedString;
}

fn parseQuotedArray(allocator: std.mem.Allocator, value: []const u8, out: *std.ArrayList([]u8)) !void {
    if (value.len < 2 or value[0] != '[' or value[value.len - 1] != ']') {
        return error.InvalidArray;
    }

    const body = std.mem.trim(u8, value[1 .. value.len - 1], " \t");
    if (body.len == 0) return;

    var i: usize = 0;
    while (i < body.len) {
        while (i < body.len and (body[i] == ' ' or body[i] == '\t' or body[i] == ',')) : (i += 1) {}
        if (i >= body.len) break;

        const parsed = try parseQuotedToken(allocator, body, i);
        try out.append(allocator, parsed.value);
        i = parsed.next_index;

        while (i < body.len and (body[i] == ' ' or body[i] == '\t')) : (i += 1) {}
        if (i < body.len) {
            if (body[i] != ',') return error.InvalidArray;
            i += 1;
        }
    }
}

test "parse manifest with native plugin metadata" {
    const gpa = std.testing.allocator;
    const input =
        \\id = "dev.ziggy.storage"
        \\version = "1.2.0"
        \\api_version = 1
        \\capabilities = ["storage", "network"]
        \\ios_spm = ["https://github.com/apple/swift-collections"]
        \\android_maven = ["com.squareup.okhttp3:okhttp:4.12.0"]
    ;

    var manifest = try PluginManifest.parse(gpa, input);
    defer manifest.deinit(gpa);

    try std.testing.expectEqualStrings("dev.ziggy.storage", manifest.id);
    try std.testing.expectEqualStrings("1.2.0", manifest.version);
    try std.testing.expectEqual(@as(u32, 1), manifest.api_version);
    try std.testing.expectEqual(@as(usize, 2), manifest.capabilities.len);
    try std.testing.expectEqualStrings("storage", manifest.capabilities[0]);
    try std.testing.expectEqualStrings("network", manifest.capabilities[1]);
    try std.testing.expectEqual(@as(usize, 1), manifest.ios_spm.len);
    try std.testing.expectEqual(@as(usize, 1), manifest.android_maven.len);
}

test "missing id is rejected" {
    const gpa = std.testing.allocator;
    const input =
        \\version = "1.0.0"
        \\api_version = 1
    ;

    try std.testing.expectError(error.MissingId, PluginManifest.parse(gpa, input));
}
