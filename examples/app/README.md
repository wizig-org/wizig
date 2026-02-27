# Full App Example

This folder demonstrates the Flutter-style Ziggy scaffold where a single app root contains platform hosts:

- `ios/`
- `android/`
- optional desktop placeholders (for example `macos/`)

Generate/update the sample:

```sh
zig build run -- create ZiggyExample examples/app/ZiggyExample
```

Run:

```sh
zig build run -- run ios examples/app/ZiggyExample/ios
zig build run -- run android examples/app/ZiggyExample/android
```
