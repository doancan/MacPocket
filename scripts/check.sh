#!/bin/bash
set -euo pipefail
MACPOCKET_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$MACPOCKET_ROOT/scripts/env.sh"
node --version
rea --version
xcrun lldb --version
xcrun --find lldb-dap
"$JAVA_HOME/bin/java" -version
rizin -v
rea doctor --client codex --provider ghidra --skill --format json | python3 -c '
import json, sys
report = json.load(sys.stdin)
for check in report["scope_checks"]:
    print(("OK" if check["ok"] else "FAIL") + ": " + check["name"] + " — " + check.get("detail", ""))
sys.exit(0 if report["healthy"] else 1)
'
