#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

require_wizig_bin

workdir="$(make_temp_dir)"
cleanup() {
  if [[ "${WIZIG_E2E_KEEP:-0}" == "1" ]]; then
    info "kept workspace: $workdir"
    return
  fi
  rm -rf "$workdir"
}
trap cleanup EXIT

packaged_root="$workdir/packaged-wizig"
copy_packaged_root "$packaged_root"

app_dir="$workdir/MultiFileApiApp"

info "[multifile-api-resolution] creating fixture app"
"$WIZIG_BIN" create MultiFileApiApp "$app_dir" --platforms ios --sdk-root "$packaged_root"

cat > "$app_dir/wizig.api.zig" <<'EOF'
pub const namespace = "dev.wizig.multifileapiapp";
pub const methods = .{
    .{ .name = "echo", .input = .string, .output = .string },
    .{ .name = "fromFeature", .input = .string, .output = .string },
};
pub const events = .{};
EOF

cat > "$app_dir/lib/feature.zig" <<'EOF'
const std = @import("std");

pub fn fromFeature(input: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "feature:{s}", .{input});
}
EOF

"$WIZIG_BIN" codegen "$app_dir"

require_file "$app_dir/lib/WizigGeneratedAppModule.zig"
grep -Fq '@import("feature.zig")' "$app_dir/lib/WizigGeneratedAppModule.zig" \
  || fail "generated app module did not import feature.zig"
grep -Fq "pub fn fromFeature" "$app_dir/lib/WizigGeneratedAppModule.zig" \
  || fail "generated app module missing fromFeature wrapper"

ffi_out="$workdir/libwizigffi"
zig build-lib -ODebug \
  --dep wizig_core \
  --dep wizig_app \
  -Mroot="$app_dir/.wizig/generated/zig/WizigGeneratedFfiRoot.zig" \
  -Mwizig_core="$app_dir/.wizig/runtime/core/src/root.zig" \
  -Mwizig_app="$app_dir/lib/WizigGeneratedAppModule.zig" \
  --name wizigffi \
  -dynamic \
  "-femit-bin=$ffi_out"

[[ -f "$ffi_out" ]] || fail "failed to build FFI with multi-file API module"

info "PASS: multi-file API resolution compiles through generated app module"
