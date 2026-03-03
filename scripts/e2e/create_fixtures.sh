#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

require_wizig_bin
mkdir -p "$WIZIG_TESTS_ROOT"

recreate_fixture() {
  local name="$1"
  local path="$2"

  rm -rf "$path"
  "$WIZIG_BIN" create "$name" "$path" --platforms ios,android --sdk-root "$REPO_ROOT"
}

info "[fixtures] regenerating fixture apps under $WIZIG_TESTS_ROOT"
recreate_fixture "WizigSmokeApp" "$FIXTURE_SMOKE_APP"
recreate_fixture "WizigPluginApp" "$FIXTURE_PLUGIN_APP"
recreate_fixture "WizigApiMatrixApp" "$FIXTURE_API_MATRIX_APP"

info "[fixtures] customizing WizigPluginApp"
rm -rf "$FIXTURE_PLUGIN_APP/plugins/plugin-hello"
cp -R "$REPO_ROOT/examples/plugin-hello" "$FIXTURE_PLUGIN_APP/plugins/plugin-hello"
"$WIZIG_BIN" plugin sync "$FIXTURE_PLUGIN_APP"

grep -Fq "dev.wizig.hello" "$FIXTURE_PLUGIN_APP/.wizig/generated/zig/generated_plugins.zig" \
  || fail "plugin fixture missing generated zig registrant entry"
grep -Fq "wizig-plugin.json" "$FIXTURE_PLUGIN_APP/.wizig/generated/swift/GeneratedPluginRegistrant.swift" \
  || fail "plugin fixture registrant did not keep json manifest path"

info "[fixtures] customizing WizigApiMatrixApp"
cat > "$FIXTURE_API_MATRIX_APP/lib/math.zig" <<'EOF'
const std = @import("std");

pub fn sum(input: i64) i64 {
    return input + 10;
}

pub fn tag(input: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "tag:{s}", .{input});
}
EOF

cat > "$FIXTURE_API_MATRIX_APP/lib/feature.zig" <<'EOF'
const std = @import("std");

pub fn fromFeature(input: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "feature:{s}", .{input});
}
EOF

"$WIZIG_BIN" codegen "$FIXTURE_API_MATRIX_APP"
grep -Fq '@import("feature.zig")' "$FIXTURE_API_MATRIX_APP/lib/WizigGeneratedAppModule.zig" \
  || fail "api matrix fixture missing feature.zig import in generated app module"
grep -Fq 'pub fn fromFeature' "$FIXTURE_API_MATRIX_APP/lib/WizigGeneratedAppModule.zig" \
  || fail "api matrix fixture missing fromFeature wrapper"

write_fixtures_manifest
require_file "$(fixture_manifest_path)"

info "PASS: regenerated Wizig fixture apps under $WIZIG_TESTS_ROOT"
