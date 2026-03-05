# FFI Design

The FFI (Foreign Function Interface) layer is the boundary between native host code and the Zig runtime. It uses a C ABI for maximum portability across iOS and Android.

## Status Codes

All FFI functions return integer status codes:

| Code | Name | Meaning |
|------|------|---------|
| `0` | `ok` | Success |
| `1` | `null_argument` | A required pointer argument was null |
| `2` | `out_of_memory` | Allocation failed |
| `3` | `invalid_argument` | Argument value was invalid |
| `255` | `internal_error` | Unexpected internal failure |

## Error Envelope

Errors are communicated through a thread-local structured envelope with three fields:

- **domain** — Error category (e.g., `"runtime"`, `"ffi"`, `"app"`)
- **code** — Numeric error code within the domain
- **message** — Human-readable error description

The envelope is set by the FFI layer when a call fails and can be read by the host after checking the status code. Thread-local storage ensures concurrent calls don't interfere with each other.

## ABI Versioning

Before making any business API calls, the host must complete a handshake:

1. **ABI version check** — Host passes its expected ABI version; the runtime validates compatibility.
2. **Contract hash validation** — Host passes the hash of the generated contract; the runtime confirms it matches the compiled contract.

If either check fails, the runtime rejects the initialization and the host receives an error before any business logic executes. This prevents subtle bugs from ABI or contract drift.

## Memory Policy

The default memory policy is:

- **Wizig-owned allocator** — The Zig runtime owns all allocations.
- **Explicit free APIs** — Host calls `wizig_bytes_free` to release returned data.
- **Arena-based** — Command execution uses arena allocators for predictable cleanup.

This minimizes host-side lifetime mistakes and keeps call sites simple. An optional host allocator injection API is reserved for advanced use cases.

## Threading Policy

- Zig runtime may use background threads freely.
- UI callbacks remain main-thread-owned by Swift/SwiftUI and Kotlin/Compose.
- Generated API must not assume host UI thread affinity for pure compute calls.

## C Header

The public C API is declared in `ffi/include/wizig.h`. This header is:

- Packaged into iOS XCFramework builds
- Used by the generated modulemap for Swift interop
- The authoritative surface for all C ABI symbols

## iOS Artifact Model

On iOS, the FFI layer is compiled into `WizigFFI.xcframework`:

- Contains `iphoneos` and `iphonesimulator` slices
- Device slice is `arm64` only; simulator supports `arm64` + `x86_64` via `lipo`
- Includes C headers and `module.modulemap` for Swift import
- Build output is deterministic and cache-friendly

## Signing and App Store Safety

The iOS build pipeline includes safety checks:

- Device framework architecture verification (`arm64` required, simulator arches rejected)
- Code signing bound to Xcode-resolved `EXPANDED_CODE_SIGN_IDENTITY`
- Private API linkage guard — build fails if the device binary links private frameworks or imports denylisted symbols
