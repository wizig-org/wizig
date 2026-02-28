//! Public Ziggy core API surface re-exported for consumers.
/// Runtime instance used by host bridges.
pub const Runtime = @import("runtime.zig").Runtime;
/// Plugin manifest schema representation.
pub const PluginManifest = @import("plugins/manifest.zig").PluginManifest;
/// In-memory plugin registry.
pub const PluginRegistry = @import("plugins/registry_codegen.zig").Registry;
/// Single plugin record entry.
pub const PluginRecord = @import("plugins/registry_codegen.zig").PluginRecord;
/// Collects plugin manifests from a directory tree.
pub const collectPluginRegistry = @import("plugins/registry_codegen.zig").collectFromDir;
/// Renders deterministic plugin lockfile text.
pub const renderPluginLockfile = @import("plugins/registry_codegen.zig").renderLockfile;
/// Renders Zig plugin registrant source.
pub const renderZigRegistrant = @import("plugins/registry_codegen.zig").renderZigRegistrant;
/// Renders Swift plugin registrant source.
pub const renderSwiftRegistrant = @import("plugins/registry_codegen.zig").renderSwiftRegistrant;
/// Renders Kotlin plugin registrant source.
pub const renderKotlinRegistrant = @import("plugins/registry_codegen.zig").renderKotlinRegistrant;
