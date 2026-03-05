# SDK Resolution

Wizig resolves SDK roots with strict precedence. Understanding this chain is important for development workflows, CI setups, and troubleshooting.

## Resolution Order

The SDK root is resolved by checking the following sources in order. The first valid root wins:

| Priority | Source | Example |
|----------|--------|---------|
| 1 | CLI flag `--sdk-root` | `wizig run . --sdk-root /path/to/wizig` |
| 2 | Environment variable `WIZIG_SDK_ROOT` | `export WIZIG_SDK_ROOT=/path/to/wizig` |
| 3 | Install-relative bundles | `../share/wizig` relative to the binary |
| 4 | Development workspace fallback | Marker files in parent directories |

## Validation

Each candidate root is validated by checking for required markers:

- `toolchains.toml` — toolchain governance policy
- Runtime and template directories — vendored assets for scaffolding

If validation fails, the resolution continues to the next candidate. If no valid root is found, the error message reports all attempted paths for debugging.

## Common Scenarios

### Development Checkout

When working from a cloned Wizig repository:

```sh
# Explicit SDK root pointing to repo
wizig create MyApp /tmp/MyApp --sdk-root /path/to/wizig

# Or via environment variable
export WIZIG_SDK_ROOT=/path/to/wizig
wizig create MyApp /tmp/MyApp
```

### Installed Binary

When Wizig is installed (e.g., via a release package), the install-relative resolution finds assets at `../share/wizig` relative to the `wizig` binary.

### CI

Set `WIZIG_SDK_ROOT` in your CI environment to point to the Wizig checkout:

```yaml
env:
  WIZIG_SDK_ROOT: ${{ github.workspace }}/wizig
```

## Troubleshooting

If SDK resolution fails:

1. Check the error output — it lists all attempted paths.
2. Verify `toolchains.toml` exists at the SDK root.
3. Use `--sdk-root` explicitly to bypass auto-resolution.
4. Run `wizig doctor --sdk-root <path>` to validate the root.
