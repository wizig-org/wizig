#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

require_wizig_bin
require_file "$(fixture_manifest_path)"

run_codegen_check() {
  local app_path="$1"
  "$WIZIG_BIN" codegen "$app_path"
  require_file "$app_path/.wizig/generated/zig/WizigGeneratedFfiRoot.zig"
  require_file "$app_path/.wizig/generated/swift/WizigGeneratedApi.swift"
  require_file "$app_path/.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt"
  require_file "$app_path/.wizig/generated/ios/wizig.h"
  require_file "$app_path/.wizig/generated/ios/WizigGeneratedApi.h"
  require_file "$app_path/.wizig/generated/ios/WizigFFI.h"
  require_file "$app_path/.wizig/generated/ios/module.modulemap"
}

run_once_check() {
  local app_path="$1"
  local label="$2"
  local log_file="$WIZIG_TESTS_ROOT/.wizig/${label}.run.log"

  set +e
  "$WIZIG_BIN" run "$app_path" --non-interactive --once >"$log_file" 2>&1
  local status=$?
  set -e

  if grep -Fq "no generated app hosts found" "$log_file"; then
    fail "$label failed due to host detection instead of target/device state"
  fi

  if [[ $status -eq 0 ]]; then
    grep -Fq "run completed (--once)" "$log_file" \
      || grep -Fq "run log:" "$log_file" \
      || fail "$label succeeded but output did not include expected run markers"
    return
  fi

  # Non-zero status is acceptable in headless environments with no devices.
  grep -E -q "no runnable targets found|no available iOS|warning: iOS device discovery failed|warning: Android device discovery failed|run log:" "$log_file" \
    || fail "$label failed with unexpected output"
}

info "[fixture-matrix] running codegen checks"
run_codegen_check "$FIXTURE_SMOKE_APP"
run_codegen_check "$FIXTURE_PLUGIN_APP"
run_codegen_check "$FIXTURE_API_MATRIX_APP"

info "[fixture-matrix] validating iOS xcframework slices from xcodebuild"
assert_wizig_ios_xcframework_slices_after_xcodebuild "$FIXTURE_SMOKE_APP"

info "[fixture-matrix] running plugin sync checks"
"$WIZIG_BIN" plugin sync "$FIXTURE_PLUGIN_APP"
grep -Fq "dev.wizig.hello" "$FIXTURE_PLUGIN_APP/.wizig/generated/zig/generated_plugins.zig" \
  || fail "plugin sync did not include dev.wizig.hello in plugin fixture"
grep -Fq "wizig-plugin.json" "$FIXTURE_PLUGIN_APP/.wizig/plugins/plugins.lock.toml" \
  || fail "plugin lock still references non-json manifest path"

info "[fixture-matrix] asserting Android SDK does not use JNA"
if grep -R -E "com\\.sun\\.jna|net\\.java\\.dev\\.jna" \
  "$REPO_ROOT/sdk/android/src" \
  "$REPO_ROOT/sdk/android/build.gradle.kts" >/dev/null; then
  fail "Android SDK still contains JNA references"
fi

info "[fixture-matrix] running deterministic --once checks"
run_once_check "$FIXTURE_SMOKE_APP" "smoke"
run_once_check "$FIXTURE_PLUGIN_APP" "plugin"
run_once_check "$FIXTURE_API_MATRIX_APP" "api-matrix"

info "[fixture-matrix] validating wrong-root diagnostic hint"
wrong_root_log="$WIZIG_TESTS_ROOT/.wizig/wrong-root.run.log"
set +e
"$WIZIG_BIN" run "$WIZIG_TESTS_ROOT" --once >"$wrong_root_log" 2>&1
wrong_root_status=$?
set -e
[[ $wrong_root_status -ne 0 ]] || fail "wizig run unexpectedly succeeded for tests root directory"
grep -Fq "choose a generated app directory" "$wrong_root_log" \
  || fail "wrong-root run did not print generated-app directory hint"

info "PASS: fixture matrix checks completed"
