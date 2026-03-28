# `src/cli/commands/codegen/root/reporting.zig`

_Language: Zig_

User-facing reporting for completed codegen passes.

## Public API

### `sourceLabel` (fn)

Returns the user-facing label for a resolved contract source.

```zig
pub fn sourceLabel(maybe_source: ?contract_source.ApiContractSource) []const u8 {
```

### `hasGeneratedChanges` (fn)

Returns whether any generated output changed during the pass.

```zig
pub fn hasGeneratedChanges(result: output_write.WriteResult) bool {
```

### `writeGenerationReport` (fn)

Writes the codegen summary for generated outputs and patched hosts.

```zig
pub fn writeGenerationReport(
    stdout: *Io.Writer,
    maybe_source: ?contract_source.ApiContractSource,
    plan: output_plan.OutputPlan,
    result: output_write.WriteResult,
    sync_result: host_sync.SyncResult,
) !void {
```
