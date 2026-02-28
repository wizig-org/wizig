#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/self_contained_create.sh"
bash "$SCRIPT_DIR/host_edits_persist_on_run.sh"
bash "$SCRIPT_DIR/multifile_api_resolution.sh"

printf 'PASS: self-contained template pipeline e2e suite completed\n'
