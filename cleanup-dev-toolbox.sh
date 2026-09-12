#!/usr/bin/env bash
set -Eeuo pipefail

BOX="${BOX:-dev}"
VSCODE_FLATPAK="${VSCODE_FLATPAK:-com.visualstudio.code}"
IDEA_FLATPAK="${IDEA_FLATPAK:-com.jetbrains.IntelliJ-IDEA-Ultimate}"
IDEA_COMMUNITY_FLATPAK="${IDEA_COMMUNITY_FLATPAK:-com.jetbrains.IntelliJ-IDEA-Community}"
ASSUME_YES=0

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--yes]

Completely removes the development environment created by setup-dev-toolbox.sh.
Run this on the Fedora Atomic host, not from inside Toolbx.

Environment variables:
  BOX                  Toolbox name to remove (default: dev)
  VSCODE_FLATPAK       VS Code Flatpak ID
  IDEA_FLATPAK         IntelliJ Ultimate Flatpak ID
  IDEA_COMMUNITY_FLATPAK IntelliJ Community Flatpak ID

Options:
  -y, --yes             Skip the destructive confirmation prompt
  -h, --help            Show this help

WARNING: this intentionally removes ~/.zshrc and user-level development
manager/config directories so setup-dev-toolbox.sh can be tested from a
clean state.
USAGE
}

while (($#)); do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ -f /run/.toolboxenv ]]; then
  echo "Run this script on the Fedora Atomic host, not from inside a toolbox." >&2
  exit 1
fi

cat <<EOF_SUMMARY
This will remove the development environment for toolbox '$BOX', including:
  - the '$BOX' Toolbx container and everything installed in it
  - ~/.zshrc and ~/.oh-my-zsh
  - SDKMAN, nvm, rustup/Cargo, and GHCup installations and managed runtimes
  - LuaLS, OpenShift oc, Codex/Copilot wrappers, Claude Code, Cursor Agent
  - Cursor desktop AppImage/configuration installed by this project
  - VS Code and IntelliJ Flatpaks, including their per-user Flatpak app data
  - generated dev-toolbox configuration and verification helpers

Your source repositories and unrelated files in your home directory are not removed.
EOF_SUMMARY

if (( ! ASSUME_YES )); then
  printf '\nType DELETE to continue: '
  read -r answer
  [[ "$answer" == "DELETE" ]] || { echo "Cancelled."; exit 0; }
fi

log "Removing toolbox '$BOX'"
if command -v toolbox >/dev/null 2>&1; then
  toolbox rm -f "$BOX" 2>/dev/null || true
else
  warn "toolbox command not found; skipping toolbox removal."
fi

log "Removing shell and language/version-manager state"
rm -rf -- \
  "$HOME/.oh-my-zsh" \
  "$HOME/.sdkman" \
  "$HOME/.nvm" \
  "$HOME/.rustup" \
  "$HOME/.cargo" \
  "$HOME/.ghcup" \
  "$HOME/.config/dev-toolbox"

# A clean setup test intentionally recreates ~/.zshrc from scratch.
rm -f -- "$HOME/.zshrc"

log "Removing manually installed developer tools"
rm -rf -- \
  "$HOME/.local/opt/lua-language-server" \
  "$HOME/.local/opt/cursor" \
  "$HOME/.local/share/cursor-agent"

rm -f -- \
  "$HOME/.local/bin/dev-shell" \
  "$HOME/.local/bin/verify-dev-toolbox" \
  "$HOME/.local/bin/lua-language-server" \
  "$HOME/.local/bin/oc" \
  "$HOME/.local/bin/codex" \
  "$HOME/.local/bin/copilot" \
  "$HOME/.local/bin/claude" \
  "$HOME/.local/bin/agent" \
  "$HOME/.local/bin/cursor-agent" \
  "$HOME/.local/bin/cursor" \
  "$HOME/.local/share/applications/cursor.desktop"

# Native Claude Code may keep installation/configuration state here.
rm -rf -- "$HOME/.claude"

# Cursor desktop/CLI user configuration and extension state. These are removed
# because this script is specifically for a complete clean reinstall test.
rm -rf -- \
  "$HOME/.config/Cursor" \
  "$HOME/.cache/Cursor" \
  "$HOME/.cursor"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

log "Removing VS Code and IntelliJ Flatpaks and their app data"
if command -v flatpak >/dev/null 2>&1; then
  for app in "$VSCODE_FLATPAK" "$IDEA_FLATPAK" "$IDEA_COMMUNITY_FLATPAK"; do
    if flatpak info --user "$app" >/dev/null 2>&1; then
      flatpak uninstall --user --delete-data -y "$app" || true
    else
      echo "$app is not installed for this user."
    fi
  done
else
  warn "flatpak command not found; skipping Flatpak cleanup."
fi

log "Cleanup verification"
failures=0

check_absent_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    printf 'FAIL  still exists: %s\n' "$path"
    failures=$((failures + 1))
  else
    printf 'PASS  removed:      %s\n' "$path"
  fi
}

check_absent_path "$HOME/.zshrc"
check_absent_path "$HOME/.oh-my-zsh"
check_absent_path "$HOME/.sdkman"
check_absent_path "$HOME/.nvm"
check_absent_path "$HOME/.rustup"
check_absent_path "$HOME/.cargo"
check_absent_path "$HOME/.ghcup"
check_absent_path "$HOME/.config/dev-toolbox"
check_absent_path "$HOME/.local/opt/lua-language-server"
check_absent_path "$HOME/.local/opt/cursor"
check_absent_path "$HOME/.local/share/cursor-agent"

if command -v toolbox >/dev/null 2>&1 && toolbox run --container "$BOX" true >/dev/null 2>&1; then
  printf 'FAIL  toolbox still exists: %s\n' "$BOX"
  failures=$((failures + 1))
else
  printf 'PASS  toolbox removed: %s\n' "$BOX"
fi

if command -v flatpak >/dev/null 2>&1; then
  for app in "$VSCODE_FLATPAK" "$IDEA_FLATPAK" "$IDEA_COMMUNITY_FLATPAK"; do
    if flatpak info --user "$app" >/dev/null 2>&1; then
      printf 'FAIL  Flatpak still installed: %s\n' "$app"
      failures=$((failures + 1))
    else
      printf 'PASS  Flatpak absent: %s\n' "$app"
    fi
  done
fi

printf '\n'
if (( failures )); then
  echo "Cleanup completed with $failures verification failure(s)." >&2
  exit 1
fi

echo "Cleanup complete. The environment is ready for a fresh setup test."
echo
echo "Next run:"
echo "  ./setup-dev-toolbox.sh 2>&1 | tee setup-full-test.log"
