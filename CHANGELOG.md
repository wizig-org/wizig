# Changelog

## 0.0.9

### Added

- CI/CD for nightly builds

### Fixed

- Fixes [#12](https://github.com/wizig-org/wizig/issues/12) via conditional allocator selection based on build mode
- Fixes [#14](https://github.com/wizig-org/wizig/issues/14) — generated Swift `withUTF8Pointer` now uses `String.withUTF8` for zero-copy pointer access instead of heap-allocating `Array(value.utf8)` on every call
- Fixes [#15](https://github.com/wizig-org/wizig/issues/15) — generated JNI bridge uses `GetStringUTFLength` (O(1)) instead of `strlen` (O(n)) for all string input paths
- Fixes [#16](https://github.com/wizig-org/wizig/issues/16) — generated JNI `new_jstring_from_bytes` uses a 512-byte stack buffer for small strings, eliminating `malloc`/`free` for ~95% of string returns
- Fixes [#17](https://github.com/wizig-org/wizig/issues/17) — generated Swift `callStringOutput` uses `String(decoding:as: UTF8.self)` instead of allocating an intermediate `Data` object
- Fix CI/CD failing for docs-checks and e2e tests.

### Changed

- Duplicate files in `ffi` and `runtime` directories been removed. Now using symlinks. Fixes [#34](https://github.com/wizig-org/wizig/issues/34)


### Known Issues

- As of zig `0.16.0-dev.2984+cb7d2b056` the builds with Xcode 26.4 results in error ([`#31658 ziglang/zig`](https://codeberg.org/ziglang/zig/issues/31658)). 

## 0.0.8

### Added

- Added sample zig std print in SDK/Templates

### Fixed

- Fixed issue in the iOS code signing flow where embedded frameworks were being re-signed on every codegen run
- Replaced `std.heap.GeneralPurposeAllocator` with `std.heap.DebugAllocator` (zig `0.16.0-dev.2984+cb7d2b056`)

### Known Issues

- As of zig `0.16.0-dev.2984+cb7d2b056` the builds with Xcode 26.4 results in error ([`#31658 ziglang/zig`](https://codeberg.org/ziglang/zig/issues/31658)). 

## 0.0.7

### Added

- Added [`CONTRIBUTION.md`](CONTRIBUTION.md) with contributor setup, build, test, docs, CI, and release guidance.
- Added direct test coverage for recently extracted helpers across codegen project analysis and platform run/discovery modules.

### Changed

- Refactored several large CLI and runtime orchestration modules into smaller documented submodules to improve maintainability and keep tracked authored source files under the 300-line target.
- Split project analysis helpers for library discovery, type discovery, and API spec merging into focused facade-plus-helper layouts.
- Split iOS and Android platform orchestration/discovery flows into smaller modules with clearer responsibilities and better local testability.
- Expanded release and packaging documentation around tag-driven builds, artifacts, and Homebrew publication.

### Fixed

- Hardened FFI boundary handling for null inbound pointers in host/runtime entrypoints.
- Reduced unnecessary iOS device re-signing by only re-signing when embedded framework contents actually change.
- Switched iOS framework comparison to streamed chunk reads instead of whole-file allocation.
- Made iOS mirror-target resolution deterministic when multiple top-level Xcode projects exist.

## Historical Releases

Detailed notes for releases published before `CHANGELOG.md` was added are available in GitHub Releases:

- [`0.0.6`](https://github.com/wizig-org/wizig/releases/tag/0.0.6)
- [`0.0.5`](https://github.com/wizig-org/wizig/releases/tag/0.0.5)
- [`0.0.4`](https://github.com/wizig-org/wizig/releases/tag/0.0.4)
- [`0.0.3`](https://github.com/wizig-org/wizig/releases/tag/0.0.3)
- [`v0.0.4-dev`](https://github.com/wizig-org/wizig/releases/tag/v0.0.4-dev)
- [`v0.0.3-dev`](https://github.com/wizig-org/wizig/releases/tag/v0.0.3-dev)
- [`v0.0.2-dev`](https://github.com/wizig-org/wizig/releases/tag/v0.0.2-dev)
- [`v0.0.2`](https://github.com/wizig-org/wizig/releases/tag/v0.0.2)
- [`v0.0.1`](https://github.com/wizig-org/wizig/releases/tag/v0.0.1)
