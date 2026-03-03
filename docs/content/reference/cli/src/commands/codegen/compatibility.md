# `cli/src/commands/codegen/compatibility.zig`

_Language: Zig_

Compatibility metadata for generated FFI bindings.

## Goals
- Provide a stable ABI version constant for runtime handshake checks.
- Derive a deterministic contract hash from the generated API surface.
- Keep host and Zig layers synchronized without requiring manual versioning.

## Hash Model
The hash includes:
- a fixed schema/version seed
- namespace
- ordered methods (`name`, `input`, `output`)
- ordered events (`name`, `payload`)

Any semantic API change should update the hash.

## Public API

### `ffi_abi_version` (const)

Current generated FFI ABI version.

Increment this when generated FFI symbol signatures or compatibility
semantics change in a non-backward-compatible way.

```zig
pub const ffi_abi_version: u32 = 1;
```

### `Metadata` (const)

Compatibility metadata embedded into generated Zig/host bindings.

## Fields
- `abi_version`: numeric ABI generation identifier.
- `contract_hash_hex`: lower-case SHA-256 digest of API surface contract.

## Lifetime
The hash string is arena-owned by the allocator passed into builders.

```zig
pub const Metadata = struct {
```

### `buildMetadata` (fn)

Builds compatibility metadata from a codegen API surface.

## Inputs
`methods` and `events` are expected to be deterministic slices from the
codegen pipeline (already sorted/merged as needed by the caller).

## Output
Returns a metadata struct that can be embedded directly into generated
Zig/Swift/Kotlin/JNI artifacts for host/runtime handshake validation.

```zig
pub fn buildMetadata(
    arena: std.mem.Allocator,
    namespace: []const u8,
    methods: anytype,
    events: anytype,
) !Metadata {
```

### `computeContractHashHex` (fn)

Computes a lower-case SHA-256 hex digest for the API contract.

## Determinism
The digest preserves declared slice order. Any method/event insertion,
removal, rename, or signature change updates the resulting hash.

```zig
pub fn computeContractHashHex(
    arena: std.mem.Allocator,
    namespace: []const u8,
    methods: anytype,
    events: anytype,
) ![]u8 {
```
