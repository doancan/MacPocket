#!/bin/bash
set -euo pipefail
MACPOCKET_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MACPOCKET_ROOT"
source scripts/env.sh
make .build/debug-smoke
rea observe-native-calls .build/debug-smoke \
  '{"breakpoints":[{"kind":"function","name":"macpocket_add"}],"duration_ms":3000,"max_events":10,"argument_registers":2}' \
  --format json > .build/lldb-rea.json
rea instrument-with-frida spawn "$MACPOCKET_ROOT/.build/debug-smoke" \
  --argument=--quiet --script-file tools/frida-smoke.js --duration-ms 250 \
  --format json > .build/frida-rea.json
rea execute-rizin-command .build/debug-smoke iIj --format json > .build/rizin-rea.json
rea decompile .build/debug-smoke _macpocket_add --provider ghidra \
  --format json > .build/ghidra-rea.json
python3 - <<'PY'
import json
from pathlib import Path

def evidence(name):
    return json.loads(Path(f'.build/{name}-rea.json').read_text())

lldb = evidence('lldb')['normalized_result']
assert lldb['process']['exit_status'] == 0, lldb['process']
assert lldb['coverage']['unresolved_breakpoints'] == [], lldb['coverage']
assert len(lldb['events']) == 1, lldb['events']
assert [int(r['value'], 16) for r in lldb['events'][0]['registers']] == [20, 22]

frida = evidence('frida')['normalized_result']
assert frida['cleanup_error'] is None, frida
assert not any(m['type'] == 'error' for m in frida['messages']), frida['messages']
payloads = [m.get('payload') for m in frida['messages']]
assert {'test': 'macpocket', 'left': 20, 'right': 22} in payloads, payloads
assert {'test': 'macpocket-result', 'result': 42} in payloads, payloads

rizin = evidence('rizin')['normalized_result']
assert rizin['exit_code'] == 0, rizin
assert not rizin['artifact_changed'], rizin
info = json.loads(rizin['stdout'])
assert info['bits'] == 64 and info['os'] == 'darwin', info
if rizin['stderr']:
    print('Rizin Mach-O bilgisi okundu; parser tanıları .build/rizin-rea.json içinde.')

ghidra = evidence('ghidra')
assert ghidra['provider']['id'] == 'ghidra', ghidra['provider']
code = json.dumps(ghidra['normalized_result'])
assert 'return' in code and 'macpocket_add' in code, code
print('LLDB breakpoint ve argümanlar: OK')
print('Frida giriş ve dönüş hook: OK')
print('Rizin Mach-O bilgisi: OK')
print('Ghidra decompilation: OK')
PY
