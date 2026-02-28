# Full App Example

This folder demonstrates the Flutter-style Wizig scaffold where a single app root contains platform hosts:

- `ios/`
- `android/`
- optional desktop placeholders (for example `macos/`)

Generate/update the sample:

```sh
zig build run -- create WizigExample examples/app/WizigExample
```

Run:

```sh
zig build run -- run ios examples/app/WizigExample/ios
zig build run -- run android examples/app/WizigExample/android
```
