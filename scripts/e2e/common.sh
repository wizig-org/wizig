#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

E2E_ROOT_DEFAULT="/Users/arata/Developer/zig/tests"
E2E_ROOT="${WIZIG_E2E_TEST_ROOT:-$E2E_ROOT_DEFAULT}"
WIZIG_BIN_DEFAULT="$REPO_ROOT/zig-out/bin/wizig"
WIZIG_BIN="${WIZIG_E2E_WIZIG_BIN:-$WIZIG_BIN_DEFAULT}"

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
