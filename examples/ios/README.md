# iOS Example

This folder contains a CLI-generated Xcode project at `examples/ios/ZiggyExample`.

Generate the project:

```sh
zig build run -- create ios ZiggyExample examples/ios/ZiggyExample
```

Build from CLI:

```sh
xcodebuild -project examples/ios/ZiggyExample/ZiggyExample.xcodeproj \
  -scheme ZiggyExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ZiggyExampleDerived \
  build
```
