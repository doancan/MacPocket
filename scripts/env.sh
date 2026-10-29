#!/bin/bash
# Shared environment for the repo's scripts. No shell profile changes required.
MACPOCKET_BREW_PREFIX="$(brew --prefix)"
export PATH="$MACPOCKET_BREW_PREFIX/bin:$PATH"
export JAVA_HOME="$(brew --prefix openjdk@25)/libexec/openjdk.jdk/Contents/Home"
export GHIDRA_INSTALL_DIR="${MACPOCKET_GHIDRA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/macpocket/toolchains/ghidra_12.1.4_PUBLIC}"
export REA_RIZIN_COMMAND="$MACPOCKET_BREW_PREFIX/bin/rizin"
