# ADR 0001: Native Host UI + Zig Core

## Status
Accepted

## Context
Ziggy targets mobile-first development with future web support. A direct cross-platform UI renderer would delay delivery and increase platform risk.

## Decision
Use native UI hosts (SwiftUI, Jetpack Compose) with shared Zig core logic accessed over a stable C ABI.

## Consequences

### Positive
- Native-quality UX/performance on iOS and Android
- Shared business logic in Zig
- ABI boundary is explicit and versionable
- Plugin ecosystem can include native SPM/Gradle dependencies

### Negative
- UI code remains platform-specific
- Plugin registration is build-time for mobile targets

## Follow-up
- Add generated plugin registrants
- Add capability gating and policy enforcement
- Define web host via Zig Wasm + JS adapters
