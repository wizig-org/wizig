# iOS Interop

This page documents the iOS-specific architecture, guarantees, and operational expectations for Wizig apps.

## Architecture

The iOS integration pipeline:

1. `wizig codegen` generates:
    - `.wizig/generated/zig/WizigGeneratedFfiRoot.zig` — Zig FFI root
    - `.wizig/generated/swift/WizigGeneratedApi.swift` — Swift API client
    - `ios/<App>/Generated/WizigGeneratedApi.swift` — Xcode project mirror
2. iOS host patch injects a deterministic Xcode shell phase: `Wizig Build iOS FFI`
3. The phase compiles Zig FFI as an Apple framework: `.wizig/generated/ios/WizigFFI.xcframework`
4. Swift runtime calls the exported ABI directly and validates:
    - ABI version handshake
    - Contract hash handshake
    - Structured last-error domain/code/message

## Required Guarantees

### Artifact Model

- Canonical iOS artifact is `WizigFFI.xcframework`.
- Build phase output is deterministic and cache-friendly.
- Debug and release use the same generated ABI surface.
- Multi-slice assembly: `iphoneos` + `iphonesimulator` slices. When available, simulator `arm64` + `x86_64` are merged via `lipo`.

### IDE Discoverability

- Swift developers use generated `WizigGeneratedApi` types from the `Wizig` module.
- Public API names are discovered from `lib/**/*.zig` and optional contract overrides.
- User-defined functions remain first-class in generated Swift wrappers.

### ABI Boundary

- C ABI signatures are the transport boundary.
- Generated Swift layer stays typed; no runtime reflection or schema parsing.
- Compatibility mismatch fails fast before first business call.

### Memory and Allocator Policy

- Default: Wizig-owned allocator + explicit free APIs (`wizig_bytes_free`).
- Minimizes host-side lifetime mistakes and keeps call sites simple.
- Future: optional host allocator injection API for advanced control.

### Threading Policy

- Zig runtime may use background threads freely.
- UI callbacks remain main-thread-owned by Swift/SwiftUI.
- Generated API does not assume host UI thread affinity for pure compute calls.

### Signing and Provisioning

- Xcode remains source-of-truth for provisioning/profile selection.
- Wizig does not manage profiles/cert creation.
- `wizig run` invokes build/sign steps only through Xcode toolchain context.

## App Store Safety

The build pipeline includes safety checks:

- Device framework architecture verification (`arm64` required, simulator arches rejected)
- Signing bound to Xcode-resolved `EXPANDED_CODE_SIGN_IDENTITY` with strict verification
- Private API linkage guard — build fails if device binary links private frameworks or imports denylisted symbols

## Zig Toolchain Selection

The Xcode build phase resolves Zig deterministically:

- Reads version from `.wizig/toolchain.lock.json`
- Supports optional network bootstrap with `WIZIG_ZIG_AUTO_INSTALL=1`
- Lock drift fails by default; override with `WIZIG_FFI_ALLOW_TOOLCHAIN_DRIFT=1`

## Sandbox Override

The pbxproj patching sets `ENABLE_USER_SCRIPT_SANDBOXING = NO` only for app target build configurations that run the Wizig phase. Project/test target configurations are left untouched.

## Operational Expectations

- `wizig create <Name>` always prepares an iOS host compatible with `wizig run`.
- `wizig codegen` is idempotent and re-runnable from Xcode build phases.
- Never manually edit generated `.wizig/generated` artifacts.
- Manual editing of host iOS sources is preserved across runs.
