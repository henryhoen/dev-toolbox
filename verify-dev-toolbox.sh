#!/usr/bin/env bash
set -uo pipefail

BOX="${BOX:-dev}"
VSCODE_FLATPAK="${VSCODE_FLATPAK:-com.visualstudio.code}"
IDEA_FLATPAK="${IDEA_FLATPAK:-com.jetbrains.IntelliJ-IDEA-Ultimate}"

PASS=0
FAIL=0
WARN=0
FAILED_TESTS=()
CHECK_TIMEOUT="${CHECK_TIMEOUT:-20}"

blue='\033[1;34m'
green='\033[1;32m'
red='\033[1;31m'
yellow='\033[1;33m'
reset='\033[0m'

section() { printf '\n%b==> %s%b\n' "$blue" "$*" "$reset"; }

check() {
  local name="$1"; shift
  local output rc
  output="$(timeout --foreground "${CHECK_TIMEOUT}s" "$@" 2>&1)"; rc=$?
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
  output="$(timeout --foreground "${CHECK_TIMEOUT}s" zsh -lc "$cmd" 2>&1)"; rc=$?
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


check_in_tmp() {
  local name="$1"; shift
  local tmp output rc
  tmp="$(mktemp -d)"

  output="$(
    cd "$tmp" &&
    timeout --foreground "${CHECK_TIMEOUT}s" "$@" 2>&1
  )"; rc=$?

  rm -rf "$tmp"

  if (( rc == 0 )); then
    ((PASS++))
    printf '%bPASS%b  %-34s %s\n' "$green" "$reset" "$name" "$(printf '%s' "$output" | head -n 1)"
  else
    ((FAIL++))
    FAILED_TESTS+=("$name")
    if (( rc == 124 )); then
      printf '%bFAIL%b  %-34s TIMEOUT after %ss\n' "$red" "$reset" "$name" "$CHECK_TIMEOUT"
    else
      printf '%bFAIL%b  %-34s rc=%d\n' "$red" "$reset" "$name" "$rc"
    fi
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" | sed 's/^/      /' | head -n 12
    fi
  fi
  return 0
}

check_shell_in_tmp() {
  local name="$1" cmd="$2"
  local tmp output rc
  tmp="$(mktemp -d)"

  output="$(
    timeout --foreground "${CHECK_TIMEOUT}s" \
      env DEV_VERIFY_TMP="$tmp" zsh -lc 'cd "$DEV_VERIFY_TMP" && eval "$1"' zsh "$cmd" 2>&1
  )"; rc=$?

  rm -rf "$tmp"

  if (( rc == 0 )); then
    ((PASS++))
    printf '%bPASS%b  %-34s %s\n' "$green" "$reset" "$name" "$(printf '%s' "$output" | tail -n 1)"
  else
    ((FAIL++))
    FAILED_TESTS+=("$name")
    if (( rc == 124 )); then
      printf '%bFAIL%b  %-34s TIMEOUT after %ss\n' "$red" "$reset" "$name" "$CHECK_TIMEOUT"
    else
      printf '%bFAIL%b  %-34s rc=%d\n' "$red" "$reset" "$name" "$rc"
    fi
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" | sed 's/^/      /' | head -n 16
    fi
  fi
  return 0
}


if [[ ! -f /run/.toolboxenv ]]; then
  section "Host checks"
  check "toolbox" toolbox --version
  check "Podman host" podman --version
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

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.ghcup/bin:$PATH"

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
check_in_tmp "neovim" nvim --version
check_in_tmp "git" git --version
check_in_tmp "GitHub CLI" gh --version
check_in_tmp "curl" curl --version
check_in_tmp "wget" wget --version
check_in_tmp "jq" jq --version
check_in_tmp "yq" yq --version
check_in_tmp "ripgrep" rg --version
check_in_tmp "fd" fd --version
check_in_tmp "fzf" fzf --version
check_in_tmp "direnv" direnv version
check_in_tmp "tmux" tmux -V
check_in_tmp "shellcheck" shellcheck --version
check_in_tmp "rsync" rsync --version
check_in_tmp "tree" tree --version

section "Native build toolchain"
check_in_tmp "gcc" gcc --version
check_in_tmp "g++" g++ --version
check_in_tmp "clang" clang --version
check_in_tmp "make" make --version
check_in_tmp "cmake" cmake --version
check_in_tmp "ninja" ninja --version
check_in_tmp "gdb" gdb --version
check_in_tmp "lldb" lldb --version
check_in_tmp "pkg-config" pkg-config --version

section "Java / SDKMAN"
check_shell "SDKMAN" 'sdk version | tail -n 1'
check_shell_in_tmp "Java" 'java --version 2>&1 | head -n 1'
check_shell_in_tmp "Maven" 'mvn --version | head -n 1'
check_shell_in_tmp "Gradle" 'gradle --version | grep -m1 "Gradle "'
check_shell_in_tmp "Quarkus CLI" 'quarkus --version'

section "Node / nvm"
check "nvm" bash -c 'source "$HOME/.nvm/nvm.sh" && nvm --version'
check_shell_in_tmp "Node" 'node --version'
check_shell_in_tmp "npm" 'npm --version'

section "AI coding tools"
check_shell_in_tmp "OpenAI Codex CLI" 'source "$HOME/.nvm/nvm.sh"; nvm use default >/dev/null; codex --version'
check_in_tmp "Claude Code" claude --version
check_in_tmp "Cursor Agent CLI" agent --version
check_shell_in_tmp "GitHub Copilot CLI" 'source "$HOME/.nvm/nvm.sh"; nvm use default >/dev/null; copilot --version'

section "Rust"
check_shell_in_tmp "rustup" 'rustup --version | head -n 1'
check_shell_in_tmp "rustc" 'rustc --version'
check_shell_in_tmp "cargo" 'cargo --version'
check_shell_in_tmp "rustfmt" 'rustfmt --version'
check_shell_in_tmp "clippy" 'cargo clippy --version'
check_shell_in_tmp "rust-analyzer" 'rust-analyzer --version'

section "Haskell / GHCup"
check_shell_in_tmp "GHCup" 'ghcup --version'
check_shell_in_tmp "GHC" 'ghc --version'
check_shell_in_tmp "Cabal" 'cabal --version | head -n 1'
check_shell_in_tmp "Stack" 'stack --version | head -n 1'
check_shell_in_tmp "Haskell Language Server" 'haskell-language-server-wrapper --version'

section "Other languages"
check_in_tmp "Go" go version
check_in_tmp "Zig" zig version
check_in_tmp "Lua" lua -v
check_in_tmp "LuaRocks" luarocks --version
check_in_tmp "Lua Language Server" "$HOME/.local/bin/lua-language-server" --version
check "LuaLS command path" bash -c 'command -v lua-language-server'
check "LuaLS resolved path" bash -c 'p="$(command -v lua-language-server)" && readlink -f "$p"'
check_in_tmp "Perl" perl -v
check "cpanm command" bash -c 'command -v cpanm >/dev/null'
check_in_tmp "cpanminus module" perl -MApp::cpanminus -e 'print "$App::cpanminus::VERSION\\n"'
check_in_tmp "Erlang" erl -version
check_in_tmp "rebar3" rebar3 version
check_in_tmp "Ruby" ruby --version
check_in_tmp "RubyGems" gem --version
check_in_tmp "GnuCOBOL" cobc --version
check_in_tmp "SBCL" sbcl --version
check_in_tmp "CLISP" clisp --version
check_in_tmp "Guile" guile --version
check_in_tmp "SWI-Prolog" swipl --version

section "Database clients"
check_in_tmp "SQLite" sqlite3 --version
check_in_tmp "PostgreSQL psql" psql --version
check_in_tmp "PostgreSQL pg_dump" pg_dump --version
check_in_tmp "PostgreSQL pg_restore" pg_restore --version

section "Containers / Kubernetes / OpenShift"
check_in_tmp "kubectl" kubectl version --client
check_in_tmp "Helm" helm version --short
check_in_tmp "OpenShift oc" oc version --client

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
