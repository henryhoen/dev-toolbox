#!/usr/bin/env bash
set -Eeuo pipefail

BOX="${BOX:-dev}"
IDEA_FLATPAK="${IDEA_FLATPAK:-com.jetbrains.IntelliJ-IDEA-Ultimate}"
VSCODE_FLATPAK="${VSCODE_FLATPAK:-com.visualstudio.code}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }

if [[ -f /run/.toolboxenv ]]; then
  echo "Run this script on the Fedora Atomic host, not from inside a toolbox." >&2
  exit 1
fi

command -v toolbox >/dev/null || { echo "toolbox is required on the host." >&2; exit 1; }
command -v flatpak >/dev/null || { echo "flatpak is required on the host." >&2; exit 1; }

log "Ensuring Flathub is configured"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

log "Installing GUI IDEs as Flatpaks"
flatpak install --user -y flathub "$VSCODE_FLATPAK" "$IDEA_FLATPAK"

# Dev Containers makes VS Code capable of attaching to the running Toolbx container.
# Failure is non-fatal because extension installation behavior can vary between builds.
flatpak run "$VSCODE_FLATPAK" --install-extension ms-vscode-remote.remote-containers >/dev/null 2>&1 || \
  warn "Could not preinstall VS Code Dev Containers extension; install 'Dev Containers' from VS Code if needed."

log "Installing Cursor desktop as a user-local AppImage"
install_cursor_desktop() {
  local arch url tmp
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64) arch="arm64" ;;
    *) warn "Unsupported architecture for Cursor desktop: $(uname -m)"; return 0 ;;
  esac
  mkdir -p "$HOME/.local/opt/cursor" "$HOME/.local/bin" "$HOME/.local/share/applications"
  url="https://api2.cursor.sh/updates/download/golden/linux-${arch}/cursor/"
  tmp="$(mktemp)"
  if curl -fL "$url" -o "$tmp"; then
    install -m 0755 "$tmp" "$HOME/.local/opt/cursor/cursor.AppImage"
    ln -sfn "$HOME/.local/opt/cursor/cursor.AppImage" "$HOME/.local/bin/cursor"
    cat > "$HOME/.local/share/applications/cursor.desktop" <<EOF
[Desktop Entry]
Name=Cursor
Comment=AI code editor
Exec=$HOME/.local/opt/cursor/cursor.AppImage %F
Icon=applications-development
Type=Application
Categories=Development;IDE;
Terminal=false
StartupNotify=true
EOF
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  else
    warn "Cursor desktop download failed."
  fi
  rm -f "$tmp"
}
install_cursor_desktop

# Cursor is VS Code-derived and can use Dev Containers to attach to the Toolbx environment.
"$HOME/.local/opt/cursor/cursor.AppImage" --install-extension ms-vscode-remote.remote-containers >/dev/null 2>&1 || \
  warn "Could not preinstall Dev Containers in Cursor; install it from Cursor Extensions if needed."

log "Creating toolbox '$BOX' if necessary"
if ! toolbox run --container "$BOX" true >/dev/null 2>&1; then
  toolbox create --container "$BOX"
else
  echo "Toolbox '$BOX' already exists."
fi

log "Installing development environment inside '$BOX'"
toolbox run --container "$BOX" env DEV_TOOLBOX_NAME="$BOX" bash -s <<'INNER'
set -Eeuo pipefail

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }

log "Updating toolbox packages"
sudo dnf upgrade --refresh -y

# Packages that are expected to exist on supported Fedora releases.
PACKAGES=(
  zsh neovim git gh curl wget unzip zip tar gzip bzip2 xz
  jq yq ripgrep fd-find tree tmux shellcheck rsync file which less man-db findutils
  procps-ng iproute bind-utils
  gcc gcc-c++ make cmake ninja-build gdb lldb clang llvm lld pkgconf
  openssl-devel libffi-devel gmp gmp-devel ncurses ncurses-compat-libs
  golang zig
  lua lua-devel luarocks
  perl perl-core perl-App-cpanminus
  erlang rebar3
  sbcl clisp guile
  gnucobol
  ruby ruby-devel readline-devel libyaml-devel
  sqlite sqlite-devel
  postgresql libpq-devel
  direnv fzf
  helm
)

log "Installing Fedora development packages"
AVAILABLE=()
MISSING=()
for pkg in "${PACKAGES[@]}"; do
  if dnf -q repoquery --available --qf '%{name}' "$pkg" 2>/dev/null | grep -Fxq "$pkg"; then
    AVAILABLE+=("$pkg")
  else
    MISSING+=("$pkg")
  fi
done
if ((${#AVAILABLE[@]})); then
  sudo dnf install -y "${AVAILABLE[@]}"
fi
if ((${#MISSING[@]})); then
  warn "These packages are not available in the enabled Fedora repositories and were skipped: ${MISSING[*]}"
fi

# SWI-Prolog package naming differs from many distros; Fedora provides this metapackage.
if dnf -q repoquery --available swi-prolog-full >/dev/null 2>&1; then
  sudo dnf install -y swi-prolog-full
elif dnf -q repoquery --available pl >/dev/null 2>&1; then
  sudo dnf install -y pl
else
  warn "SWI-Prolog package not found in enabled repositories."
fi

log "Installing kubectl from the upstream Kubernetes RPM repository"
K8S_MINOR="${K8S_MINOR:-v1.37}"
sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<K8SREPO
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/rpm/repodata/repomd.xml.key
K8SREPO
sudo dnf install -y kubectl

mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" "$HOME/.config/dev-toolbox"

log "Installing Oh My Zsh"
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

log "Installing SDKMAN"
if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  curl -fsSL 'https://get.sdkman.io?rcupdate=false' | bash
fi

log "Installing nvm"
if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
  NVM_TAG="$(curl -fsSLI https://github.com/nvm-sh/nvm/releases/latest | awk -F/ 'tolower($1)=="location:" {gsub("\\r",""); print $NF}' | tail -1)"
  if [[ -z "$NVM_TAG" ]]; then NVM_TAG="v0.40.7"; fi
  PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh | bash"
fi

log "Installing rustup"
if [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

log "Installing GHCup and initial Haskell toolchain"
if [[ ! -x "$HOME/.ghcup/bin/ghcup" ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | \
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1 sh
fi

export PATH="$HOME/.ghcup/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# Initial installs only. The updater intentionally does not update these managed SDK/tool versions.
if [[ -x "$HOME/.ghcup/bin/ghcup" ]]; then
  ghcup install ghc --set || true
  ghcup install cabal --set || true
  ghcup install hls --set || true
  ghcup install stack --set || true
fi

if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
  "$HOME/.cargo/bin/rustup" toolchain install stable || true
  "$HOME/.cargo/bin/rustup" default stable || true
  "$HOME/.cargo/bin/rustup" component add rustfmt clippy rust-analyzer || true
fi

if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.nvm/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
fi

log "Installing AI coding CLIs"
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # Codex and GitHub Copilot CLI are officially distributed through npm.
  source "$HOME/.nvm/nvm.sh"
  nvm use default >/dev/null
  npm install -g @openai/codex@latest @github/copilot@latest

  # Keep these commands usable even with the Oh My Zsh nvm plugin in lazy mode.
  for tool in codex copilot; do
    cat > "$HOME/.local/bin/$tool" <<EOF
#!/usr/bin/env bash
set -e
export NVM_DIR="\$HOME/.nvm"
. "\$NVM_DIR/nvm.sh"
NODE_BIN="\$(dirname "\$(nvm which default)")"
exec "\$NODE_BIN/$tool" "\$@"
EOF
    chmod +x "$HOME/.local/bin/$tool"
  done
fi

# Anthropic recommends the native installer; npm installation is deprecated.
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# Cursor's terminal Agent is independent from the Cursor desktop AppImage.
if ! command -v agent >/dev/null 2>&1; then
  curl https://cursor.com/install -fsS | bash
fi

if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  sdk install java || true
  sdk install maven || true
  sdk install gradle || true
  sdk install quarkus || true
fi

log "Installing/updating Lua Language Server"
install_luals() {
  local arch asset tag tmp
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64) arch="arm64" ;;
    *) warn "Unsupported architecture for LuaLS binary: $(uname -m)"; return 0 ;;
  esac

  tag="$(curl -fsSLI https://github.com/LuaLS/lua-language-server/releases/latest | awk -F/ 'tolower($1)=="location:" {gsub("\\r",""); print $NF}' | tail -1)"
  [[ -n "$tag" ]] || { warn "Could not determine latest LuaLS release."; return 0; }
  asset="lua-language-server-${tag}-linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  curl -fL "https://github.com/LuaLS/lua-language-server/releases/download/${tag}/${asset}" -o "$tmp/luals.tar.gz"
  rm -rf "$HOME/.local/opt/lua-language-server"
  mkdir -p "$HOME/.local/opt/lua-language-server"
  tar -xzf "$tmp/luals.tar.gz" -C "$HOME/.local/opt/lua-language-server"
  ln -sfn "$HOME/.local/opt/lua-language-server/bin/lua-language-server" "$HOME/.local/bin/lua-language-server"
  printf '%s\n' "$tag" > "$HOME/.local/opt/lua-language-server/.version"
  rm -rf "$tmp"
}
install_luals

log "Installing/updating OpenShift oc client"
install_oc() {
  local arch url tmp
  case "$(uname -m)" in
    x86_64) arch="linux" ;;
    aarch64) arch="linux-arm64" ;;
    *) warn "Unsupported architecture for oc binary: $(uname -m)"; return 0 ;;
  esac
  url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  if curl -fL "$url" -o "$tmp/oc.tar.gz"; then
    tar -xzf "$tmp/oc.tar.gz" -C "$tmp"
    install -m 0755 "$tmp/oc" "$HOME/.local/bin/oc"
  else
    warn "Automatic oc download failed. Install the client matching your OpenShift cluster manually."
  fi
  rm -rf "$tmp"
}
install_oc

log "Writing managed zsh configuration"
cat > "$HOME/.config/dev-toolbox/zshrc" <<'ZSHCONF'
# Managed by setup-dev-toolbox.sh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

# Load nvm lazily and honor .nvmrc when entering projects.
zstyle ':omz:plugins:nvm' lazy yes
zstyle ':omz:plugins:nvm' autoload yes
zstyle ':omz:plugins:nvm' silent-autoload yes

plugins=(
  git dnf sudo extract
  podman kubectl oc helm
  mvn gradle sdk
  npm nvm
  golang
  rust
  cabal
  rebar
  ruby gem
  perl cpanm
  postgres
  rsync fzf direnv
  colored-man-pages command-not-found history-substring-search
)

source "$ZSH/oh-my-zsh.sh"

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.ghcup/bin:$PATH"

# The Oh My Zsh `sdk` plugin provides SDKMAN completion but does not initialize SDKMAN.
# Keep SDKMAN initialization at the bottom so its selected JAVA_HOME/PATH win.
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
ZSHCONF

# Put one stable managed hook into ~/.zshrc without clobbering personal additions.
START='# >>> dev-toolbox managed >>>'
END='# <<< dev-toolbox managed <<<'
TMP_RC="$(mktemp)"
if [[ -f "$HOME/.zshrc" ]]; then
  awk -v s="$START" -v e="$END" '
    $0==s {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$HOME/.zshrc" > "$TMP_RC"
fi
cat > "$HOME/.zshrc" <<EOFZ
$START
[[ -f "\$HOME/.config/dev-toolbox/zshrc" ]] && source "\$HOME/.config/dev-toolbox/zshrc"
$END
EOFZ
cat "$TMP_RC" >> "$HOME/.zshrc" 2>/dev/null || true
rm -f "$TMP_RC"

log "Creating convenience wrappers"
cat > "$HOME/.local/bin/dev-shell" <<EOS
#!/usr/bin/env bash
exec toolbox run --container "$DEV_TOOLBOX_NAME" zsh -l
EOS
chmod +x "$HOME/.local/bin/dev-shell"

log "Toolbox installation complete"
printf '\nUse: toolbox enter %s\nThen start: zsh\n\n' "$DEV_TOOLBOX_NAME"
INNER

log "Installing verification helper"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/verify-dev-toolbox" <<'VERIFY_SCRIPT_EOF'
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
VERIFY_SCRIPT_EOF
chmod +x "$HOME/.local/bin/verify-dev-toolbox"

log "Verifying complete development environment"
if ! "$HOME/.local/bin/verify-dev-toolbox"; then
  echo
  warn "One or more verification checks failed. Paste the complete verification output when asking for a fix."
  exit 1
fi

log "Done"
echo "Toolbox: $BOX"
echo "VS Code: $VSCODE_FLATPAK"
echo "IntelliJ: $IDEA_FLATPAK"
echo
echo "For VS Code, start the '$BOX' toolbox and use Dev Containers -> Attach to Running Container."
echo "IntelliJ can directly see SDKMAN/GHCup/rustup files under your shared home; for toolbox-only system tools, use its terminal/toolchain container support where applicable."
