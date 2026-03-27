# Changelog

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
