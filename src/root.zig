//! Compatibility root module that re-exports Wizig core API.
const wizig_core = @import("wizig_core");

/// Runtime instance type.
pub const Runtime = wizig_core.Runtime;
/// Plugin manifest schema type.
pub const PluginManifest = wizig_core.PluginManifest;
