# Android Example

This folder contains the legacy per-platform Android scaffold path.

Preferred workflow is generating a full app root with `ziggy create` and using the nested Android host at `.../android`.

Generate from CLI:

```sh
zig build run -- create ZiggyExample examples/app/ZiggyExample
```

Run tests:

```sh
GRADLE_USER_HOME=/tmp/gradle-home gradle -p examples/app/ZiggyExample/android test
```
