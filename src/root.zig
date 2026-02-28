//! Compatibility root module that re-exports Ziggy core API.
const ziggy_core = @import("ziggy_core");

/// Runtime instance type.
pub const Runtime = ziggy_core.Runtime;
/// Plugin manifest schema type.
pub const PluginManifest = ziggy_core.PluginManifest;
