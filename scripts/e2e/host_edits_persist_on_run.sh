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

shim_bin="$workdir/shim-bin"
mkdir -p "$shim_bin"
write_gradle_stub "$shim_bin"
write_run_shims "$shim_bin"

packaged_root="$workdir/packaged-wizig"
copy_packaged_root "$packaged_root"

app_dir="$workdir/HostEditApp"

info "[host-edit-persistence] creating fixture app"
PATH="$shim_bin:$PATH" "$WIZIG_BIN" create HostEditApp "$app_dir" --platforms ios,android --sdk-root "$packaged_root"

ios_file="$(find "$app_dir/ios" -type f -name project.pbxproj | head -n 1 || true)"
android_file="$(find "$app_dir/android" -type f -name MainActivity.kt | head -n 1 || true)"

[[ -n "$ios_file" ]] || fail "unable to locate iOS host file for persistence check"
[[ -n "$android_file" ]] || fail "unable to locate Android host file for persistence check"

printf '\n// WIZIG_E2E_IOS_EDIT\n' >> "$ios_file"
printf '\n// WIZIG_E2E_ANDROID_EDIT\n' >> "$android_file"

before_ios_sha="$(sha_file "$ios_file")"
before_android_sha="$(sha_file "$android_file")"

run_once() {
  local run_no="$1"
  local log_file="$workdir/run-${run_no}.log"

  set +e
  PATH="$shim_bin:$PATH" "$WIZIG_BIN" run "$app_dir" --non-interactive --once >"$log_file" 2>&1
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    cat "$log_file" >&2
    fail "wizig run unexpectedly succeeded in deterministic no-device fixture (run #$run_no)"
  fi

  local after_ios_sha
  local after_android_sha
  after_ios_sha="$(sha_file "$ios_file")"
  after_android_sha="$(sha_file "$android_file")"

  [[ "$before_ios_sha" == "$after_ios_sha" ]] || {
    cat "$log_file" >&2
    fail "iOS host file changed after wizig run #$run_no: $ios_file"
  }
  [[ "$before_android_sha" == "$after_android_sha" ]] || {
    cat "$log_file" >&2
    fail "Android host file changed after wizig run #$run_no: $android_file"
  }

  grep -Fq "WIZIG_E2E_IOS_EDIT" "$ios_file" || fail "missing iOS sentinel after run #$run_no"
  grep -Fq "WIZIG_E2E_ANDROID_EDIT" "$android_file" || fail "missing Android sentinel after run #$run_no"
}

info "[host-edit-persistence] running wizig run twice (expected failures with no devices)"
run_once 1
run_once 2

info "PASS: host edits persisted across repeated wizig run invocations"
