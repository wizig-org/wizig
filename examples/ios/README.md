# iOS Example

This folder contains the legacy per-platform iOS scaffold path.

Preferred workflow is generating a full app root with `wizig create` and using the nested iOS host at `.../ios`.

Generate the project:

```sh
zig build run -- create WizigExample examples/app/WizigExample
```

Build from CLI:

```sh
xcodebuild -project examples/app/WizigExample/ios/WizigExample.xcodeproj \
  -scheme WizigExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/WizigExampleDerived \
  build
```
