# Android Example

This folder contains a CLI-generated Gradle project at `examples/android/ZiggyExample`.

Generate from CLI:

```sh
zig build run -- create android ZiggyExample examples/android/ZiggyExample
```

Run tests:

```sh
GRADLE_USER_HOME=/tmp/gradle-home gradle -p examples/android/ZiggyExample test
```
