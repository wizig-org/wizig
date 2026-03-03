#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/create_fixtures.sh"
bash "$SCRIPT_DIR/run_fixture_matrix.sh"

printf 'PASS: self-contained template pipeline e2e suite completed\n'
