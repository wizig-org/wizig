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

packaged_root="$workdir/packaged-wizig"
copy_packaged_root "$packaged_root"

app_dir="$workdir/SelfContainedApp"

info "[self-contained-create] wizig binary: $WIZIG_BIN"
info "[self-contained-create] workspace: $workdir"

PATH="$shim_bin:$PATH" \
WIZIG_IDE_TEMPLATES_DO_NOT_USE="/path/that/does/not/exist" \
"$WIZIG_BIN" create SelfContainedApp "$app_dir" --platforms ios,android --sdk-root "$packaged_root"

require_file "$app_dir/.wizig/sdk/ios/Package.swift"
require_file "$app_dir/.wizig/runtime/ffi/src/root.zig"
require_file "$app_dir/ios/SelfContainedApp.xcodeproj/project.pbxproj"
require_file "$app_dir/ios/SelfContainedApp/Generated/WizigGeneratedApi.swift"
require_file "$app_dir/android/app/build.gradle.kts"
require_file "$app_dir/lib/WizigGeneratedAppModule.zig"
require_file "$app_dir/.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt"
require_file "$app_dir/.wizig/sdk/ios/Sources/Wizig/WizigGeneratedApi.swift"
require_file "$app_dir/.wizig/sdk/android/src/main/kotlin/dev/wizig/WizigGeneratedApi.kt"
require_file "$app_dir/.wizig/generated/android/jniLibs/.gitkeep"
require_file "$app_dir/android/gradlew"

[[ ! -f "$app_dir/ios/project.yml" ]] || fail "legacy iOS project.yml should not be scaffolded"
[[ ! -d "$app_dir/ios/Sources" ]] || fail "legacy iOS Sources/ scaffold should not be created"
grep -Fq "IPHONEOS_DEPLOYMENT_TARGET = 18.0;" "$app_dir/ios/SelfContainedApp.xcodeproj/project.pbxproj" \
  || fail "iOS deployment target is not normalized to 18.0"
grep -Fq "compileSdk = 36" "$app_dir/android/app/build.gradle.kts" \
  || fail "Android compileSdk is not normalized to 36"
grep -Fq "minSdk = 26" "$app_dir/android/app/build.gradle.kts" \
  || fail "Android minSdk is not normalized to 26"
grep -Fq 'jniLibs.directories.add(rootProject.file("../.wizig/generated/android/jniLibs").path)' "$app_dir/android/app/build.gradle.kts" \
  || fail "Android jniLibs sourceSet is not wired to .wizig/generated/android/jniLibs via non-deprecated directory wiring"
grep -Fq 'kotlin.directories.add(rootProject.file("../.wizig/sdk/android/src/main/kotlin").path)' "$app_dir/android/app/build.gradle.kts" \
  || fail "Android Kotlin sourceSet is not wired to .wizig/sdk/android/src/main/kotlin"
grep -Fq 'val requestedWizigAbi: String? = providers.gradleProperty("wizig.ffi.abi").orNull' "$app_dir/android/app/build.gradle.kts" \
  || fail "Android FFI ABI selection property is not wired for host-managed build ownership"
grep -Fq 'onlyIf { requestedWizigAbi == null || requestedWizigAbi == abi }' "$app_dir/android/app/build.gradle.kts" \
  || fail "Android host-managed FFI tasks are not filtered by requested ABI"
grep -Fq 'inputs.file(generatedRoot.resolve("WizigGeneratedFfiRoot.zig"))' "$app_dir/android/app/build.gradle.kts" \
  || fail "Android host-managed FFI task inputs are not declared for incremental execution"
grep -Fq 'tasks.matching { it.name.startsWith("merge") && it.name.endsWith("JniLibFolders") }.configureEach {' "$app_dir/android/app/build.gradle.kts" \
  || fail "Android merge*JniLibFolders tasks are not explicitly wired to host-managed FFI producers"
if grep -Fq 'val buildWizigFfiArm64 =' "$app_dir/android/app/build.gradle.kts"; then
  fail "Android scaffold still uses legacy fixed per-ABI task wiring"
fi
if grep -Fq "{APP_NAME}" "$app_dir/android/app/src/main/java/dev/wizig/selfcontainedapp/MainActivity.kt"; then
  fail "Android MainActivity still contains unresolved {APP_NAME} token"
fi

if [[ -d "$packaged_root/templates/seeds" || -d "$packaged_root/templates/spec" ]]; then
  fail "packaged root unexpectedly contains seeds/spec; test setup invalid"
fi

info "PASS: self-contained wizig create succeeded without external IDE template inputs"
