#!/usr/bin/env bash
set -uo pipefail

BOX="${BOX:-dev}"
VSCODE_FLATPAK="${VSCODE_FLATPAK:-com.visualstudio.code}"
IDEA_FLATPAK="${IDEA_FLATPAK:-com.jetbrains.IntelliJ-IDEA-Ultimate}"

PASS=0
FAIL=0
WARN=0
FAILED_TESTS=()

blue='\033[1;34m'
green='\033[1;32m'
red='\033[1;31m'
yellow='\033[1;33m'
reset='\033[0m'

section() { printf '\n%b==> %s%b\n' "$blue" "$*" "$reset"; }

check() {
  local name="$1"; shift
  local output rc
  output="$("$@" 2>&1)"; rc=$?
  if (( rc == 0 )); then
    ((PASS++))
    printf '%bPASS%b  %-34s %s\n' "$green" "$reset" "$name" "$(printf '%s' "$output" | head -n 1)"
  else
    ((FAIL++))
    FAILED_TESTS+=("$name")
    printf '%bFAIL%b  %-34s rc=%d\n' "$red" "$reset" "$name" "$rc"
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" | sed 's/^/      /' | head -n 12
    fi
  fi
  return 0
}

check_shell() {
  local name="$1" cmd="$2"
  local output rc
  output="$(zsh -lic "$cmd" 2>&1)"; rc=$?
  if (( rc == 0 )); then
    ((PASS++))
    printf '%bPASS%b  %-34s %s\n' "$green" "$reset" "$name" "$(printf '%s' "$output" | tail -n 1)"
  else
    ((FAIL++))
    FAILED_TESTS+=("$name")
    printf '%bFAIL%b  %-34s rc=%d\n' "$red" "$reset" "$name" "$rc"
    printf '%s\n' "$output" | sed 's/^/      /' | head -n 16
  fi
  return 0
}

if [[ ! -f /run/.toolboxenv ]]; then
  section "Host checks"
  check "toolbox" toolbox --version
  check "dev toolbox exists" toolbox run --container "$BOX" true
  check "VS Code Flatpak" flatpak info --user "$VSCODE_FLATPAK"
  check "IntelliJ Flatpak" flatpak info --user "$IDEA_FLATPAK"
  check "Cursor AppImage" test -x "$HOME/.local/opt/cursor/cursor.AppImage"
  check "Cursor desktop entry" test -s "$HOME/.local/share/applications/cursor.desktop"

  section "Toolbox checks"
  SELF="$(readlink -f "$0")"
  toolbox run --container "$BOX" env VERIFY_DEV_TOOLBOX_INNER=1 BOX="$BOX" bash "$SELF"
  rc=$?
  if (( rc != 0 )); then
    printf '\n%bToolbox verification reported failures.%b\n' "$red" "$reset"
    exit "$rc"
  fi

  printf '\n%bHost verification complete.%b\n' "$green" "$reset"
  exit 0
fi

section "Environment"
printf 'OS:           '; source /etc/os-release; printf '%s\n' "${PRETTY_NAME:-unknown}"
printf 'Architecture: %s\n' "$(uname -m)"
printf 'Kernel:       %s\n' "$(uname -r)"
printf 'PATH:         %s\n' "$PATH"

section "Toolbox identity and shell"
check "toolbox marker" test -f /run/.toolboxenv
check "zsh" zsh --version
check "Oh My Zsh directory" test -f "$HOME/.oh-my-zsh/oh-my-zsh.sh"
check_shell "Oh My Zsh startup" 'source ~/.zshrc >/dev/null; print -r -- OMZ_STARTUP_OK'

# Verify every plugin configured by setup-dev-toolbox.sh exists in the installed OMZ tree.
OMZ_PLUGINS=(
  git dnf sudo extract podman kubectl oc helm mvn gradle sdk npm nvm golang rust
  cabal rebar ruby gem perl cpanm postgres rsync fzf direnv colored-man-pages
  command-not-found history-substring-search
)
for plugin in "${OMZ_PLUGINS[@]}"; do
  check "OMZ plugin: $plugin" test -d "$HOME/.oh-my-zsh/plugins/$plugin"
done

section "Core CLI tools"
check "neovim" nvim --version
check "git" git --version
check "GitHub CLI" gh --version
check "curl" curl --version
check "wget" wget --version
check "jq" jq --version
check "yq" yq --version
check "ripgrep" rg --version
check "fd" fd --version
check "fzf" fzf --version
check "direnv" direnv version
check "tmux" tmux -V
check "shellcheck" shellcheck --version
check "rsync" rsync --version
check "tree" tree --version

section "Native build toolchain"
check "gcc" gcc --version
check "g++" g++ --version
check "clang" clang --version
check "make" make --version
check "cmake" cmake --version
check "ninja" ninja --version
check "gdb" gdb --version
check "lldb" lldb --version
check "pkg-config" pkg-config --version

section "Java / SDKMAN"
check_shell "SDKMAN" 'sdk version | tail -n 1'
check_shell "Java" 'java --version 2>&1 | head -n 1'
check_shell "Maven" 'mvn --version | head -n 1'
check_shell "Gradle" 'gradle --version | grep -m1 "Gradle "'
check_shell "Quarkus CLI" 'quarkus --version'

section "Node / nvm"
check_shell "nvm" 'nvm --version'
check_shell "Node" 'node --version'
check_shell "npm" 'npm --version'

section "AI coding tools"
check_shell "OpenAI Codex CLI" 'source "$HOME/.nvm/nvm.sh"; nvm use default >/dev/null; codex --version'
check "Claude Code" claude --version
check "Cursor Agent CLI" agent --version
check_shell "GitHub Copilot CLI" 'source "$HOME/.nvm/nvm.sh"; nvm use default >/dev/null; copilot --version'

section "Rust"
check_shell "rustup" 'rustup --version | head -n 1'
check_shell "rustc" 'rustc --version'
check_shell "cargo" 'cargo --version'
check_shell "rustfmt" 'rustfmt --version'
check_shell "clippy" 'cargo clippy --version'
check_shell "rust-analyzer" 'rust-analyzer --version'

section "Haskell / GHCup"
check_shell "GHCup" 'ghcup --version'
check_shell "GHC" 'ghc --version'
check_shell "Cabal" 'cabal --version | head -n 1'
check_shell "Stack" 'stack --version | head -n 1'
check_shell "Haskell Language Server" 'haskell-language-server-wrapper --version'

section "Other languages"
check "Go" go version
check "Zig" zig version
check "Lua" lua -v
check "LuaRocks" luarocks --version
check "Lua Language Server" lua-language-server --version
check "Perl" perl -v
check "cpanm" cpanm --version
check "Erlang" erl -version
check "rebar3" rebar3 version
check "Ruby" ruby --version
check "RubyGems" gem --version
check "GnuCOBOL" cobc --version
check "SBCL" sbcl --version
check "CLISP" clisp --version
check "Guile" guile --version
check "SWI-Prolog" swipl --version

section "Database clients"
check "SQLite" sqlite3 --version
check "PostgreSQL psql" psql --version
check "PostgreSQL pg_dump" pg_dump --version
check "PostgreSQL pg_restore" pg_restore --version

section "Containers / Kubernetes / OpenShift"
check "Podman host integration" podman --version
check "kubectl" kubectl version --client
check "Helm" helm version --short
check "OpenShift oc" oc version --client

section "PATH and managed files"
check "~/.local/bin in PATH" bash -c 'command -v lua-language-server >/dev/null && command -v oc >/dev/null'
check "LuaLS version marker" test -s "$HOME/.local/opt/lua-language-server/.version"
check "managed zsh config" test -s "$HOME/.config/dev-toolbox/zshrc"

printf '\n============================================================\n'
printf 'Verification summary: %b%d passed%b, %b%d failed%b\n' "$green" "$PASS" "$reset" "$red" "$FAIL" "$reset"
if (( FAIL > 0 )); then
  printf '%bFailed checks:%b\n' "$red" "$reset"
  printf '  - %s\n' "${FAILED_TESTS[@]}"
  printf '\nPaste the complete output of this verifier when asking for a fix.\n'
  exit 1
fi
printf '%bEverything verified successfully.%b\n' "$green" "$reset"
