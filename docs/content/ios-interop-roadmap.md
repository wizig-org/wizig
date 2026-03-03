# iOS Interop Roadmap

## Goal Alignment

This roadmap translates Wizig's core goals into iOS-specific implementation
rules:

- native SwiftUI UX with Zig as backend
- direct C ABI transport (no JSON or serialization bridge)
- sub-second iteration bias for edit/build/run loops
- IDE-discoverable APIs generated from Zig source
- App Store-compliant packaging/signing flow

## Current iOS Architecture

1. `wizig codegen` generates:
   - `.wizig/generated/zig/WizigGeneratedFfiRoot.zig`
   - `.wizig/generated/swift/WizigGeneratedApi.swift`
   - `ios/<App>/Generated/WizigGeneratedApi.swift` mirror
2. iOS host patch injects a deterministic Xcode shell phase:
   - `Wizig Build iOS FFI`
3. The phase compiles Zig FFI as an Apple framework and mirrors:
   - `.wizig/generated/ios/WizigFFI.xcframework`
4. Swift runtime calls the exported ABI directly and validates:
   - ABI version handshake
   - contract hash handshake
   - structured last-error domain/code/message

## Required iOS Guarantees

### 1. Artifact Model

- Canonical iOS artifact is `WizigFFI.xcframework`.
- Build phase output must remain deterministic and cache-friendly.
- Debug and release should use the same generated ABI surface.

### 2. IDE Discoverability

- Swift developers should use generated `WizigGeneratedApi` types from the
  `Wizig` module.
- Public API names are discovered from `lib/**/*.zig` and optional contract
  overrides.
- User-defined functions remain first-class in generated Swift wrappers.

### 3. ABI Boundary

- C ABI signatures remain the transport boundary.
- Generated Swift layer stays typed; no runtime reflection or schema parsing.
- Compatibility mismatch must fail fast before first business call.

### 4. Memory and Allocator Policy

- Default policy: Wizig-owned allocator + explicit free APIs (`wizig_bytes_free`).
- This minimizes host-side lifetime mistakes and keeps host call sites simple.
- Future extension: optional host allocator injection API for advanced control.

### 5. Threading Policy

- Zig runtime may use background threads freely.
- UI callbacks remain main-thread-owned by Swift/SwiftUI.
- Generated API must not assume host UI thread affinity for pure compute calls.

### 6. Signing and Provisioning

- Xcode remains source-of-truth for provisioning/profile selection.
- Wizig does not manage profiles/cert creation.
- `wizig run` may invoke build/sign steps only through Xcode toolchain context.

## Delta Status

Completed:

1. Multi-slice XCFramework assembly in one path:
   - build phase now compiles `iphoneos` + `iphonesimulator` slices.
   - when available, simulator `arm64` + `x86_64` are merged via `lipo`.
2. Generated C header + modulemap packaging for optional direct C imports:
   - codegen now emits iOS interop headers/modulemap under `.wizig/generated/ios`.
   - framework packaging stage copies headers and `module.modulemap` into each slice.
3. Dedicated iOS smoke test asserting framework slice completeness metadata:
   - e2e fixture matrix builds one iOS host via `xcodebuild`.
   - it inspects `WizigFFI.xcframework/Info.plist` and asserts both device and simulator slices.
4. App-target-scoped script sandbox override:
   - pbxproj patching now sets `ENABLE_USER_SCRIPT_SANDBOXING = NO` only for
     app target build configurations that run the Wizig phase.
   - project/test target configurations are left untouched.
5. App Store safety checks in iOS framework packaging:
   - device framework architecture is verified (`arm64` required, simulator
     arches rejected).
   - signing now binds to Xcode-resolved `EXPANDED_CODE_SIGN_IDENTITY` with
     strict verification, without fallback identity probing.
6. Deterministic Zig toolchain selection in Xcode phase:
   - build phase resolves Zig version from `.wizig/toolchain.lock.json`.
   - optional network bootstrap is supported with `WIZIG_ZIG_AUTO_INSTALL=1`
     for lock-pinned Zig versions.
   - lock drift fails by default; explicit override is
     `WIZIG_FFI_ALLOW_TOOLCHAIN_DRIFT=1`.
7. Private API linkage guard for App Store safety:
   - build phase fails if the device binary links private frameworks.
   - build phase fails on denylisted imported private symbols.
   - fixture matrix validates the generated `iphoneos` slice with `otool`/`nm`.

Remaining:

1. Explicit docs for Swift call patterns that include user-defined structs once
   struct codegen support lands.

## Operational Expectations

- `wizig create <Name>` always prepares an iOS host compatible with `wizig run`.
- `wizig codegen` remains idempotent and re-runnable from Xcode build phases.
- No manual editing of generated `.wizig/generated` artifacts.
- Manual editing of host iOS sources remains preserved across runs.
