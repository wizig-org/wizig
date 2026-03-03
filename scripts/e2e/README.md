# E2E: Self-Contained Template Pipeline

Run the full e2e suite:

```sh
scripts/e2e/self_contained_template_pipeline.sh
```

Run checks individually:

```sh
scripts/e2e/create_fixtures.sh
scripts/e2e/run_fixture_matrix.sh
```

Defaults:

- Fixture workspace root: `/Users/arata/Developer/zig/tests`
- Wizig binary: `zig-out/bin/wizig`

Optional overrides:

- `WIZIG_TESTS_ROOT`: override fixture root location.
- `WIZIG_E2E_TEST_ROOT`: backward-compatible override for fixture root.
- `WIZIG_E2E_WORK_ROOT`: alternate root for temporary scratch directories used by legacy scripts.
- `WIZIG_E2E_WIZIG_BIN`: alternate wizig executable.
- `WIZIG_E2E_REQUIRE_IOS_SLICE=1`: fail instead of skip when iOS XCFramework slice smoke-check tooling is missing.
- `WIZIG_E2E_KEEP=1`: keep test workspaces after execution for debugging.
