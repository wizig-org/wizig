//! iOS target discovery and resolution helpers.
const std = @import("std");

const ios_discovery = @import("../ios_discovery.zig");
const text_utils = @import("../text_utils.zig");
const types = @import("../types.zig");

const context = @import("context.zig");

/// Resolves the concrete iOS target to launch for a run invocation.
pub fn resolveSelectedDevice(ctx: *const context.RunContext) !types.IosDevice {
    if (ctx.options.skip_device_discovery) {
        return resolvePreselectedIosDevice(ctx);
    }
    return discoverAndChooseIosDevice(ctx);
}

/// Discovers simulators and physical devices, then prompts or filters to one target.
fn discoverAndChooseIosDevice(ctx: *const context.RunContext) !types.IosDevice {
    var all_targets = std.ArrayList(types.IosDevice).empty;
    defer all_targets.deinit(ctx.arena);

    const simulators = try ios_discovery.discoverIosDevices(ctx.arena, ctx.io, ctx.stderr);
    const supported_ids = try ios_discovery.discoverIosSupportedDestinationIds(
        ctx.arena,
        ctx.io,
        ctx.stderr,
        ctx.options.project_dir,
        ctx.xcode_project,
        ctx.scheme,
    );
    const filtered_sims = if (supported_ids.len == 0)
        simulators
    else
        try ios_discovery.filterIosDevicesBySupportedIds(ctx.arena, simulators, supported_ids);

    for (filtered_sims) |sim| {
        try all_targets.append(ctx.arena, sim);
    }

    const physical = ios_discovery.discoverIosPhysicalDevices(ctx.arena, ctx.io) catch &[_]types.IosDevice{};
    for (physical) |dev| {
        try all_targets.append(ctx.arena, dev);
    }

    if (all_targets.items.len == 0) {
        try ctx.stderr.writeAll("error: no available iOS simulators or devices found\n");
        return error.RunFailed;
    }

    const targets = try all_targets.toOwnedSlice(ctx.arena);
    return ios_discovery.chooseIosDevice(
        ctx.arena,
        ctx.io,
        ctx.stderr,
        ctx.stdout,
        targets,
        ctx.options.device_selector,
        ctx.options.non_interactive,
    );
}

/// Validates a preselected target without prompting and preserves the legacy fallback behavior.
fn resolvePreselectedIosDevice(ctx: *const context.RunContext) !types.IosDevice {
    const udid = ctx.options.device_selector orelse {
        try ctx.stderr.writeAll("error: internal preselected iOS run requires --device\n");
        return error.RunFailed;
    };

    const physical = ios_discovery.discoverIosPhysicalDevices(ctx.arena, ctx.io) catch &[_]types.IosDevice{};
    for (physical) |dev| {
        if (std.mem.eql(u8, dev.udid, udid)) return dev;
    }

    const supported_ids = try ios_discovery.discoverIosSupportedDestinationIds(
        ctx.arena,
        ctx.io,
        ctx.stderr,
        ctx.options.project_dir,
        ctx.xcode_project,
        ctx.scheme,
    );
    if (supported_ids.len > 0 and !text_utils.containsString(supported_ids, udid)) {
        try ctx.stderr.print("error: selected iOS target '{s}' is not supported by scheme '{s}'\n", .{ udid, ctx.scheme });
        return error.RunFailed;
    }

    return .{
        .name = udid,
        .udid = udid,
        .runtime = "unknown",
        .state = "Unknown",
        .kind = .simulator,
    };
}
