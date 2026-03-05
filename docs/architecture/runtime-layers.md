# Runtime Layers

Wizig applications are structured as a four-layer stack. Each layer has a clear responsibility and well-defined interface to adjacent layers.

## Layer 1: Host UI

The topmost layer is the native platform UI:

- **iOS**: SwiftUI app target
- **Android**: Jetpack Compose app module

Host UI code is written entirely in the platform's native language (Swift/Kotlin). There is no cross-platform UI abstraction — each platform uses its own idioms and design patterns.

The host UI layer calls into the generated bridge layer to invoke Zig-backed business logic and subscribes to events emitted from the Zig runtime.

## Layer 2: Generated Bridge

The bridge layer consists of generated clients and event interfaces in Swift, Kotlin, and Zig:

- **Swift**: `WizigGeneratedApi.swift` — typed method calls and event sink protocols
- **Kotlin**: `WizigGeneratedApi.kt` — typed method calls and event sink interfaces
- **Zig**: `WizigGeneratedApi.zig` — FFI root binding the app domain to the C ABI surface

Generated from `lib/**/*.zig` public function discovery (with optional contract overrides via `wizig.api.zig` or `wizig.api.json`).

Bridge code is a build artifact — never hand-edit. Regenerate with `wizig codegen`.

## Layer 3: FFI/Runtime

The FFI layer exports C ABI symbols and provides runtime primitives:

**Key modules:**

| Module | Source | Purpose |
|--------|--------|---------|
| `wizig_ffi` | `ffi/src/root.zig` | C ABI bridge; exports `wizig_runtime_*`, `wizig_ffi_*` symbols |
| `wizig_core` | `core/src/root.zig` | Runtime primitives, plugin manifest, registry codegen |

**FFI characteristics:**

- Integer status codes: `ok=0`, `null_argument=1`, `out_of_memory=2`, `invalid_argument=3`, `internal_error=255`
- Thread-local structured error envelope (domain/code/message)
- ABI version handshake + contract hash validation before API calls
- C header at `ffi/include/wizig.h`

See [FFI Design](ffi-design.md) for detailed documentation.

## Layer 4: App Domain

The bottom layer is application business logic written in Zig under `lib/`.

- Public functions (`pub fn`) are automatically discovered by codegen.
- Functions receive host-provided arguments and return typed results over the C ABI boundary.
- The app domain has no knowledge of platform specifics — it is pure Zig logic.

## Data Flow

A typical host-to-Zig call flows through all four layers:

```
SwiftUI View (Layer 1)
  → WizigGeneratedApi.echo(input) (Layer 2 - Swift)
    → wizig_ffi_echo(ptr, len) (Layer 3 - C ABI)
      → app.echo(input, allocator) (Layer 4 - Zig)
      ← returns result bytes
    ← returns status code + result pointer
  ← returns Swift String
← UI updates with result
```

Events flow in the reverse direction: Zig runtime emits events through the FFI layer, which the generated bridge delivers to host-registered event sinks.

## Run Pipeline

`wizig run` executes a unified flow through these layers:

1. Resolve project root and available hosts
2. Run codegen preflight (Layer 2 generation)
3. Discover runnable iOS/Android targets
4. Select target (interactive or non-interactive)
5. Delegate to platform build/install/launch
6. Write run log to `.wizig/logs/run.log`
