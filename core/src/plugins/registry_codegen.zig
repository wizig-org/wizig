//! Plugin registry collection and registrant source generation.
const collector = @import("registry_codegen/collector.zig");
const render_kotlin = @import("registry_codegen/render_kotlin.zig");
const render_lockfile = @import("registry_codegen/render_lockfile.zig");
const render_swift = @import("registry_codegen/render_swift.zig");
const render_zig = @import("registry_codegen/render_zig.zig");
const types = @import("registry_codegen/types.zig");

/// Plugin file path paired with parsed manifest contents.
pub const PluginRecord = types.PluginRecord;
/// In-memory registry of discovered plugins.
pub const Registry = types.Registry;

/// Collects plugin manifests from the given `plugins_dir`.
pub const collectFromDir = collector.collectFromDir;
/// Renders deterministic lockfile text for all plugin records.
pub const renderLockfile = render_lockfile.renderLockfile;
/// Renders Zig registrant source from discovered plugins.
pub const renderZigRegistrant = render_zig.renderZigRegistrant;
/// Renders Swift registrant source from discovered plugins.
pub const renderSwiftRegistrant = render_swift.renderSwiftRegistrant;
/// Renders Kotlin registrant source from discovered plugins.
pub const renderKotlinRegistrant = render_kotlin.renderKotlinRegistrant;
