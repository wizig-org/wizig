# `src/cli/run/platform/android_gradle_migration/patch.zig`

_Language: Zig_

In-memory Android Gradle build script migration helpers.

## Public API

### `old_jni_libs_line` (const)

No declaration docs available.

```zig
pub const old_jni_libs_line =
```

### `new_jni_libs_line` (const)

No declaration docs available.

```zig
pub const new_jni_libs_line =
```

### `old_zig_command_line` (const)

No declaration docs available.

```zig
pub const old_zig_command_line = "            \"zig\",\n";
```

### `new_zig_command_line` (const)

No declaration docs available.

```zig
pub const new_zig_command_line = "            discoverWizigZigBinary(),\n";
```

### `old_zig_command_inline` (const)

No declaration docs available.

```zig
pub const old_zig_command_inline = "commandLine(\"zig\",";
```

### `new_zig_command_inline` (const)

No declaration docs available.

```zig
pub const new_zig_command_inline = "commandLine(discoverWizigZigBinary(),";
```

### `old_optimize_line` (const)

No declaration docs available.

```zig
pub const old_optimize_line = "            \"-OReleaseFast\",\n";
```

### `new_optimize_line` (const)

No declaration docs available.

```zig
pub const new_optimize_line = "            \"-O${requestedWizigOptimize}\",\n";
```

### `old_optimize_inline` (const)

No declaration docs available.

```zig
pub const old_optimize_inline = "\"-OReleaseFast\",";
```

### `new_optimize_inline` (const)

No declaration docs available.

```zig
pub const new_optimize_inline = "\"-O${requestedWizigOptimize}\",";
```

### `malformed_optimize_error_line` (const)

No declaration docs available.

```zig
pub const malformed_optimize_error_line =
```

### `fixed_optimize_error_line` (const)

No declaration docs available.

```zig
pub const fixed_optimize_error_line =
```

### `java_file_check_line` (const)

No declaration docs available.

```zig
pub const java_file_check_line = "        if (java.io.File(candidate).canExecute()) return candidate\n";
```

### `root_file_check_line` (const)

No declaration docs available.

```zig
pub const root_file_check_line = "        if (rootProject.file(candidate).canExecute()) return candidate\n";
```

### `old_local_properties_block` (const)

No declaration docs available.

```zig
pub const old_local_properties_block =
```

### `new_local_properties_block` (const)

No declaration docs available.

```zig
pub const new_local_properties_block =
```

### `abi_suffix_marker` (const)

No declaration docs available.

```zig
pub const abi_suffix_marker = "fun abiTaskSuffix(abi: String): String =";
```

### `optimize_marker` (const)

No declaration docs available.

```zig
pub const optimize_marker = "val requestedWizigOptimize: String =";
```

### `zig_discovery_marker` (const)

No declaration docs available.

```zig
pub const zig_discovery_marker = "fun discoverWizigZigBinary(): String {";
```

### `optimize_block` (const)

No declaration docs available.

```zig
pub const optimize_block =
```

### `zig_discovery_block` (const)

No declaration docs available.

```zig
pub const zig_discovery_block =
```

### `patchBuildGradleKtsText` (fn)

Applies in-memory text migrations for `build.gradle.kts`.

```zig
pub fn patchBuildGradleKtsText(
    arena: std.mem.Allocator,
    original: []const u8,
) ![]const u8 {
```
