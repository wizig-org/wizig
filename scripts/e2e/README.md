# E2E: Self-Contained Template Pipeline

Run the full e2e suite:

```sh
scripts/e2e/self_contained_template_pipeline.sh
```

Run checks individually:

```sh
scripts/e2e/self_contained_create.sh
scripts/e2e/host_edits_persist_on_run.sh
```

Defaults:

- Test workspace root: `/Users/arata/Developer/zig/tests`
- Wizig binary: `zig-out/bin/wizig`

Optional overrides:

- `WIZIG_E2E_TEST_ROOT`: alternate root for temporary e2e directories.
- `WIZIG_E2E_WIZIG_BIN`: alternate wizig executable.
- `WIZIG_E2E_KEEP=1`: keep test workspaces after execution for debugging.
