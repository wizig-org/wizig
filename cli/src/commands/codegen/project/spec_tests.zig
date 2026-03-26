//! Test aggregator for API spec helpers.
//!
//! The concrete tests live in the focused helper modules so each concern stays
//! close to the implementation it validates.

test {
    _ = @import("spec/defaults.zig");
    _ = @import("spec/equality.zig");
    _ = @import("spec/merge.zig");
}
