const std = @import("std");

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    app_name: []u8,

    pub fn init(allocator: std.mem.Allocator, app_name: []const u8) !Runtime {
        return .{
            .allocator = allocator,
            .app_name = try allocator.dupe(u8, app_name),
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.allocator.free(self.app_name);
        self.* = undefined;
    }

    pub fn echo(self: *const Runtime, input: []const u8, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ self.app_name, input });
    }
};

test "runtime echo prefixes app name" {
    const gpa = std.testing.allocator;

    var runtime = try Runtime.init(gpa, "demo");
    defer runtime.deinit();

    const echoed = try runtime.echo("ping", gpa);
    defer gpa.free(echoed);

    try std.testing.expectEqualStrings("demo:ping", echoed);
}
