# iOS Example

This folder contains the legacy per-platform iOS scaffold path.

Preferred workflow is generating a full app root with `ziggy create` and using the nested iOS host at `.../ios`.

Generate the project:

```sh
zig build run -- create ZiggyExample examples/app/ZiggyExample
```

Build from CLI:

```sh
xcodebuild -project examples/app/ZiggyExample/ios/ZiggyExample.xcodeproj \
  -scheme ZiggyExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ZiggyExampleDerived \
  build
```
