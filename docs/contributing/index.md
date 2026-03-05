# How to Contribute

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork and create a feature branch:

    ```sh
    git clone https://github.com/<you>/wizig.git
    cd wizig
    git checkout -b my-feature
    ```

3. Set up your development environment — see [Development Requirements](../getting-started/development-requirements.md).

4. Build and run tests:

    ```sh
    zig build
    zig build test
    ```

## Development Workflow

### Build Commands

| Command | Purpose |
|---------|---------|
| `zig build` | Build CLI + FFI libraries + install assets |
| `zig build test` | Run all test suites |
| `zig build e2e` | Run end-to-end tests |
| `zig build run -- <cmd>` | Run CLI commands |
| `zig build docs` | Generate documentation site |

### Running Individual Test Suites

The `test` step aggregates five named suites:

| Suite | Root Source |
|-------|------------|
| `core-tests` | `core/src/root.zig` |
| `ffi-tests` | `ffi/src/root.zig` |
| `runtime-ffi-tests` | `runtime/ffi/src/root.zig` |
| `compatibility-tests` | `src/root.zig` |
| `cli-tests` | `cli/src/main.zig` |

Tests are standard Zig inline `test` blocks — no external test runner.

## Pull Request Process

1. Ensure all tests pass: `zig build test`
2. Run end-to-end tests if you changed CLI behavior: `zig build e2e`
3. If you changed `toolchains.toml`, regenerate templates and docs:

    ```sh
    python3 tools/templategen/generate_templates.py --out build/generated/templates
    python3 tools/toolchains/render_docs.py
    ```

4. Push your branch and open a PR against `main`.
5. CI will run tests, e2e, and docs checks automatically.

## What to Work On

- Check open issues on GitHub for bugs and feature requests.
- Look for issues labeled `good first issue` for beginner-friendly tasks.
- Check the [Architecture Overview](../architecture/overview.md) to understand the system before making changes.

## Code of Conduct

Be respectful and constructive. Focus on the technical merits of contributions.
