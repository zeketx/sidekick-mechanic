#!/usr/bin/env bash
# Drive the Sidekick Mechanic iPhone app on a Mac.
# Linux: doctor records the unmet Xcode precondition and exits 2.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"
exec python3 "$ROOT/.cursor/skills/verify-sidekick/scripts/verify_sidekick.py" "$@"
