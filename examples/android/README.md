# Android Example

This folder contains the legacy per-platform Android scaffold path.

Preferred workflow is generating a full app root with `wizig create` and using the nested Android host at `.../android`.

Generate from CLI:

```sh
zig build run -- create WizigExample examples/app/WizigExample
```

Run tests:

```sh
GRADLE_USER_HOME=/tmp/gradle-home gradle -p examples/app/WizigExample/android test
```
