#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WIZIG_TESTS_ROOT_DEFAULT="/Users/arata/Developer/zig/tests"
WIZIG_TESTS_ROOT="${WIZIG_TESTS_ROOT:-${WIZIG_E2E_TEST_ROOT:-$WIZIG_TESTS_ROOT_DEFAULT}}"
E2E_ROOT="${WIZIG_E2E_WORK_ROOT:-$WIZIG_TESTS_ROOT}"
WIZIG_BIN_DEFAULT="$REPO_ROOT/zig-out/bin/wizig"
WIZIG_BIN="${WIZIG_E2E_WIZIG_BIN:-$WIZIG_BIN_DEFAULT}"

FIXTURE_SMOKE_APP="$WIZIG_TESTS_ROOT/WizigSmokeApp"
FIXTURE_PLUGIN_APP="$WIZIG_TESTS_ROOT/WizigPluginApp"
FIXTURE_API_MATRIX_APP="$WIZIG_TESTS_ROOT/WizigApiMatrixApp"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

info() {
  printf '%s\n' "$1"
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "expected file missing: $path"
}

sha_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi
  fail "no sha256 utility found (tried shasum and sha256sum)"
}

make_temp_dir() {
  mkdir -p "$E2E_ROOT"
  mktemp -d "$E2E_ROOT/wizig-e2e-XXXXXX"
}

fixture_manifest_path() {
  printf '%s/.wizig/fixtures.json\n' "$WIZIG_TESTS_ROOT"
}

write_fixtures_manifest() {
  local manifest_path
  manifest_path="$(fixture_manifest_path)"
  mkdir -p "$(dirname "$manifest_path")"
  cat > "$manifest_path" <<EOF
{
  "schema_version": 1,
  "generated_by": "scripts/e2e/create_fixtures.sh",
  "fixtures": [
    { "name": "WizigSmokeApp", "path": "$FIXTURE_SMOKE_APP" },
    { "name": "WizigPluginApp", "path": "$FIXTURE_PLUGIN_APP" },
    { "name": "WizigApiMatrixApp", "path": "$FIXTURE_API_MATRIX_APP" }
  ]
}
EOF
}

require_wizig_bin() {
  [[ -x "$WIZIG_BIN" ]] || fail "wizig binary not executable: $WIZIG_BIN"
}

copy_packaged_root() {
  local out_root="$1"
  local source_root="$REPO_ROOT/zig-out/share/wizig"
  if [[ ! -d "$source_root" ]]; then
    source_root="$REPO_ROOT"
  fi

  mkdir -p "$out_root"

  # Mirror the installed SDK payload shape used by `wizig create --sdk-root`.
  # The create flow now writes `.wizig/toolchain.lock.json`, which requires
  # loading policy from `${sdk_root}/toolchains.toml` in addition to
  # sdk/runtime/templates assets.
  cp -R "$source_root/sdk" "$out_root/sdk"
  cp -R "$source_root/runtime" "$out_root/runtime"
  cp -R "$source_root/templates" "$out_root/templates"
  cp "$source_root/toolchains.toml" "$out_root/toolchains.toml"

  # Simulate a packaged install where developer seed/spec sources are absent.
  rm -rf "$out_root/templates/seeds" "$out_root/templates/spec"

  [[ -f "$out_root/templates/app/README.md" ]] || fail "packaged templates are incomplete: missing templates/app/README.md"
  [[ -f "$out_root/toolchains.toml" ]] || fail "packaged SDK root is incomplete: missing toolchains.toml"
}

write_gradle_stub() {
  local shim_bin="$1"
  cat > "$shim_bin/gradle" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && "$1" == "init" ]]; then
  mkdir -p gradle/wrapper app
  exit 0
fi

if [[ $# -ge 1 && "$1" == "wrapper" ]]; then
  mkdir -p gradle/wrapper
  cat > gradlew <<'EOF2'
#!/usr/bin/env bash
echo "gradle wrapper stub"
EOF2
  chmod +x gradlew
  cat > gradlew.bat <<'EOF2'
@echo off
echo gradle wrapper stub
EOF2
  cat > gradle/wrapper/gradle-wrapper.properties <<'EOF2'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-9.3.1-all.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF2
  exit 0
fi

echo "gradle stub: unsupported command: $*" >&2
exit 1
SH
  chmod +x "$shim_bin/gradle"
}

write_run_shims() {
  local shim_bin="$1"

  cat > "$shim_bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ge 5 && "$1" == "simctl" && "$2" == "list" && "$3" == "devices" && "$4" == "available" && "$5" == "--json" ]]; then
  cat <<'EOF2'
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-2":[{"name":"iPhone 16","udid":"SIM-UDID-1","state":"Shutdown","isAvailable":true}]}}
EOF2
  exit 0
fi

echo "xcrun stub: unsupported command: $*" >&2
exit 1
SH
  chmod +x "$shim_bin/xcrun"

  cat > "$shim_bin/adb" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ge 2 && "$1" == "devices" && "$2" == "-l" ]]; then
  echo "List of devices attached"
  exit 0
fi

echo "adb stub: unsupported command: $*" >&2
exit 1
SH
  chmod +x "$shim_bin/adb"
}

require_command_or_skip() {
  local command_name="$1"
  local requirement_flag="${WIZIG_E2E_REQUIRE_IOS_SLICE:-0}"
  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$requirement_flag" == "1" ]]; then
    fail "missing required command for iOS slice smoke check: $command_name"
  fi
  info "[fixture-matrix] skipping iOS slice smoke check (missing command: $command_name)"
  return 1
}

assert_wizig_ios_xcframework_slices_after_xcodebuild() {
  local app_path="$1"

  require_command_or_skip "xcodebuild" || return 0
  require_command_or_skip "/usr/libexec/PlistBuddy" || return 0

  local ios_dir="$app_path/ios"
  local xcodeproj
  xcodeproj="$(find "$ios_dir" -maxdepth 1 -type d -name "*.xcodeproj" | head -n 1 || true)"
  [[ -n "$xcodeproj" ]] || fail "unable to find .xcodeproj under: $ios_dir"

  local scheme
  scheme="$(basename "$xcodeproj" .xcodeproj)"

  local derived_data="$app_path/.wizig/generated/ios/e2e-derived-data"
  rm -rf "$derived_data"

  xcodebuild \
    -project "$xcodeproj" \
    -scheme "$scheme" \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived_data" \
    build >/dev/null

  local xcframework_dir="$app_path/.wizig/generated/ios/WizigFFI.xcframework"
  local plist="$xcframework_dir/Info.plist"
  require_file "$plist"

  local idx=0
  local has_iphoneos=0
  local has_iphonesimulator=0
  local iphoneos_binary=""

  while /usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$idx" "$plist" >/dev/null 2>&1; do
    local platform variant library_id
    platform="$(/usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$idx:SupportedPlatform" "$plist" 2>/dev/null || true)"
    variant="$(/usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$idx:SupportedPlatformVariant" "$plist" 2>/dev/null || true)"
    library_id="$(/usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$idx:LibraryIdentifier" "$plist" 2>/dev/null || true)"

    [[ -n "$library_id" ]] || fail "xcframework entry $idx missing LibraryIdentifier: $plist"
    local binary_path="$xcframework_dir/$library_id/WizigFFI.framework/WizigFFI"
    require_file "$binary_path"

    if [[ "$platform" == "ios" && -z "$variant" ]]; then
      has_iphoneos=1
      iphoneos_binary="$binary_path"
    fi
    [[ "$platform" == "ios" && "$variant" == "simulator" ]] && has_iphonesimulator=1

    idx=$((idx + 1))
  done

  [[ "$idx" -gt 0 ]] || fail "xcframework has no AvailableLibraries entries: $plist"
  [[ "$has_iphoneos" == "1" ]] || fail "missing iphoneos slice in: $xcframework_dir"
  [[ "$has_iphonesimulator" == "1" ]] || fail "missing iphonesimulator slice in: $xcframework_dir"

  if require_command_or_skip "xcrun"; then
    local links private_links undef private_symbols denylist_regex
    links="$(xcrun otool -L "$iphoneos_binary" 2>/dev/null || true)"
    [[ -n "$links" ]] || fail "failed to inspect linked dylibs for: $iphoneos_binary"

    private_links="$(printf '%s\n' "$links" | awk 'NR>1 {print $1}' | grep -E '(^|/)PrivateFrameworks/[^[:space:]]+\.framework/' || true)"
    [[ -z "$private_links" ]] || fail "private framework linkage detected in iOS device slice: $private_links"

    if ! undef="$(xcrun nm -u -j "$iphoneos_binary" 2>/dev/null)"; then
      fail "failed to inspect imported symbols for: $iphoneos_binary"
    fi
    denylist_regex="${WIZIG_IOS_PRIVATE_SYMBOL_DENYLIST_REGEX:-^(_MGCopyAnswer|_MGGetBoolAnswer|_OBJC_(CLASS|METACLASS)_[$]_LSApplicationWorkspace|_OBJC_(CLASS|METACLASS)_[$]_LSApplicationProxy)$}"
    private_symbols="$(printf '%s\n' "$undef" | grep -E "$denylist_regex" || true)"
    [[ -z "$private_symbols" ]] || fail "private iOS symbols imported by device slice: $private_symbols"
  fi
}
