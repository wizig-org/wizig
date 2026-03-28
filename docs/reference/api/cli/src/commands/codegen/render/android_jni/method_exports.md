# `cli/src/commands/codegen/render/android_jni/method_exports.zig`

_Language: Zig_

Per-method Android JNI export generation.

Generates `JNIEXPORT` C functions that bridge each `ApiMethod` from
Kotlin/Java to the underlying Wizig FFI C ABI.  String inputs use
`GetStringUTFLength` (O(1)) rather than `strlen` (O(n)) because the
JVM already knows the encoded length.

## Public API

### `appendMethodExports` (fn)

Appends one `JNIEXPORT` function per method to `out`.

Each generated function:
1. Validates / converts the Java input value.
2. Calls the corresponding `wizig_api_<name>` FFI symbol.
3. Converts the output back to a JNI type and returns it.

```zig
pub fn appendMethodExports(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
```
