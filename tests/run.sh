#!/usr/bin/env bash
# Run all tests. Nothing here touches your real notifications or history:
# the backend tests use a temp HOME/XDG_STATE_HOME/store and stubbed sound
# players.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/sync-ui.sh --check
node tests/model.test.js
bash tests/backend.sh
bash tests/prune.sh
bash tests/autohide.sh
