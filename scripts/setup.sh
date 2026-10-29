#!/bin/bash
set -euo pipefail
MACPOCKET_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Bu kurulum macOS içindir." >&2
  exit 1
fi
command -v brew >/dev/null || { echo "Önce https://brew.sh üzerinden Homebrew kurun." >&2; exit 1; }
xcrun --find clang >/dev/null
xcrun --find lldb >/dev/null
brew bundle --file "$MACPOCKET_ROOT/Brewfile"
npm install --global rea-agents@6.8.0 --allow-scripts=frida
"$MACPOCKET_ROOT/scripts/install-ghidra.sh"
source "$MACPOCKET_ROOT/scripts/env.sh"
rea setup --client codex --yes
"$MACPOCKET_ROOT/scripts/check.sh"
echo "REA araçlarını yüklemek için Codex'i yeniden başlatın."
