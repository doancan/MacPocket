#!/bin/bash
set -euo pipefail
MACPOCKET_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$MACPOCKET_ROOT/scripts/env.sh"
exec rea "$@"
