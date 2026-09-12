#!/usr/bin/env bash
set -Eeuo pipefail

BOX="${BOX:-dev}"
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

log "Installing/updating Flatpak applications"
flatpak install --user -y flathub "$VSCODE_FLATPAK"
flatpak update --user -y

log "Installing/updating JetBrains Toolbox on the host"
install_jetbrains_toolbox() {
  local distribution metadata_url download_url version tmp binary
  case "$(uname -m)" in
    x86_64) distribution="linux" ;;
    aarch64) distribution="linuxARM64" ;;
    *) warn "Unsupported architecture for JetBrains Toolbox: $(uname -m)"; return 1 ;;
  esac

  metadata_url="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
  tmp="$(mktemp -d)"
  curl -fsSL "$metadata_url" -o "$tmp/toolbox.json"
  read -r version download_url < <(
    python3 - "$distribution" "$tmp/toolbox.json" <<'PYTOOLBOX'
import json, sys
dist, path = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)["TBA"][0]
print(data["version"], data["downloads"][dist]["link"])
PYTOOLBOX
  )

  [[ -n "$version" && -n "$download_url" ]] || { warn "Could not resolve the latest JetBrains Toolbox release"; return 1; }

  mkdir -p "$HOME/.local/opt/jetbrains-toolbox" "$HOME/.local/bin"
  curl -fL "$download_url" -o "$tmp/jetbrains-toolbox.tar.gz"
  rm -rf "$HOME/.local/opt/jetbrains-toolbox"
  mkdir -p "$HOME/.local/opt/jetbrains-toolbox"
  tar -xzf "$tmp/jetbrains-toolbox.tar.gz" -C "$HOME/.local/opt/jetbrains-toolbox" --strip-components=1

  binary="$HOME/.local/opt/jetbrains-toolbox/bin/jetbrains-toolbox"
  [[ -x "$binary" ]] || { warn "JetBrains Toolbox executable not found after extraction"; return 1; }
  ln -sfn "$binary" "$HOME/.local/bin/jetbrains-toolbox"
  printf '%s\n' "$version" > "$HOME/.local/opt/jetbrains-toolbox/.version"

  mkdir -p "$HOME/.local/share/applications"
  cat > "$HOME/.local/share/applications/jetbrains-toolbox.desktop" <<EOF_TOOLBOX_DESKTOP
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Comment=Install and manage JetBrains IDEs
Exec=$HOME/.local/bin/jetbrains-toolbox
Icon=applications-development
Terminal=false
Categories=Development;IDE;
StartupNotify=true
EOF_TOOLBOX_DESKTOP
  chmod 0644 "$HOME/.local/share/applications/jetbrains-toolbox.desktop"
  command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

  echo "JetBrains Toolbox installed: $version"
}
install_jetbrains_toolbox

# Dev Containers makes VS Code capable of attaching to the running Toolbx container.
# Failure is non-fatal because extension installation behavior can vary between builds.
flatpak run "$VSCODE_FLATPAK" --install-extension ms-vscode-remote.remote-containers >/dev/null 2>&1 || \
  warn "Could not preinstall VS Code Dev Containers extension; install 'Dev Containers' from VS Code if needed."

log "Installing/updating Cursor desktop as a user-local AppImage"
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

# Do not launch Cursor during setup.
# Cursor's AppImage may remain in the foreground when invoked with --install-extension,
# which would block this installer. Install the Dev Containers extension from Cursor
# after first launch if desired.

log "Creating toolbox '$BOX' if necessary"
if ! toolbox run --container "$BOX" true >/dev/null 2>&1; then
  toolbox create --container "$BOX"
else
  echo "Toolbox '$BOX' already exists."
fi

log "Converging development environment inside '$BOX'"
toolbox run --container "$BOX" env DEV_TOOLBOX_NAME="$BOX" bash -s <<'INNER'
set -Eeuo pipefail

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }

log "Updating toolbox packages"
sudo dnf upgrade --refresh -y

# Packages that are expected to exist on supported Fedora releases.
PACKAGES=(
  zsh neovim git gh curl unzip zip tar gzip bzip2 xz
  jq yq ripgrep fd-find tree tmux ShellCheck rsync file which less man-db findutils
  procps-ng iproute bind-utils
  gcc gcc-c++ make cmake ninja-build gdb lldb clang llvm lld pkgconf
  openssl-devel libffi-devel gmp gmp-devel ncurses ncurses-compat-libs
  golang zig
  lua lua-devel luarocks
  perl perl-App-cpanminus
  erlang erlang-rebar3
  sbcl clisp guile30
  gnucobol
  ruby ruby-devel readline-devel libyaml-devel
  sqlite sqlite-devel
  postgresql libpq-devel
  direnv fzf
  helm
)

log "Selecting Fedora wget package"
if rpm -q wget2-wget >/dev/null 2>&1; then
  echo "wget2-wget is already installed."
elif rpm -q wget1-wget >/dev/null 2>&1; then
  echo "wget1-wget is already installed."
elif dnf -q repoquery --available wget2-wget >/dev/null 2>&1; then
  sudo dnf install -y wget2-wget
elif dnf -q repoquery --available wget1-wget >/dev/null 2>&1; then
  sudo dnf install -y wget1-wget
else
  warn "No Fedora wget provider package was found."
fi

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

# Keep the mutable Toolbx environment tidy after upgrades.
sudo dnf autoremove -y || true

# Install only the SWI-Prolog core system.  The larger swi-prolog-full/pl
# metapackages pull in GUI/Java integration that is unnecessary for this CLI
# development toolbox.
if dnf -q repoquery --available swi-prolog-core >/dev/null 2>&1; then
  sudo dnf install -y swi-prolog-core
elif dnf -q repoquery --available swi-prolog-cli >/dev/null 2>&1; then
  sudo dnf install -y swi-prolog-cli
elif dnf -q repoquery --available swi-prolog-nox >/dev/null 2>&1; then
  sudo dnf install -y swi-prolog-nox
else
  warn "A minimal SWI-Prolog package was not found in enabled repositories."
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

# Fedora's guile30 package installs guile3.0. Provide the conventional
# `guile` command in the user-local path expected by tooling.
if command -v guile3.0 >/dev/null 2>&1; then
  ln -sfn "$(command -v guile3.0)" "$HOME/.local/bin/guile"
fi

log "Installing/updating Oh My Zsh"
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
elif [[ -x "$HOME/.oh-my-zsh/tools/upgrade.sh" ]]; then
  ZSH="$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh/tools/upgrade.sh" || warn "Oh My Zsh update failed"
fi

log "Installing/updating SDKMAN manager"
if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  curl -fsSL 'https://get.sdkman.io?rcupdate=false' | bash
fi

if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  set +u
  # shellcheck disable=SC1090
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  sdk selfupdate || warn "SDKMAN self-update failed"
  sdk update || warn "SDKMAN metadata update failed"
  set -u
fi

log "Installing/updating nvm manager"
NVM_TAG="$(curl -fsSLI https://github.com/nvm-sh/nvm/releases/latest | awk -F/ 'tolower($1)=="location:" {gsub("\\r",""); print $NF}' | tail -1)"
if [[ -z "$NVM_TAG" ]]; then NVM_TAG="v0.40.7"; fi
if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
  PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh | bash"
else
  PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh | bash" || warn "nvm update failed"
fi

log "Installing/updating rustup manager"
if [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
else
  "$HOME/.cargo/bin/rustup" self update || warn "rustup self-update failed"
fi

log "Installing/updating GHCup manager"
if [[ ! -x "$HOME/.ghcup/bin/ghcup" ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | \
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1 sh
else
  "$HOME/.ghcup/bin/ghcup" upgrade || warn "GHCup update failed"
fi

export PATH="$HOME/.ghcup/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# Bootstrap manager-controlled toolchains only when they are missing.
# Once present, their versions are intentionally left under user control.
if [[ -x "$HOME/.ghcup/bin/ghcup" ]]; then
  command -v ghc >/dev/null 2>&1 || ghcup install ghc --set || true
  command -v cabal >/dev/null 2>&1 || ghcup install cabal --set || true
  command -v haskell-language-server-wrapper >/dev/null 2>&1 || ghcup install hls --set || true
  command -v stack >/dev/null 2>&1 || ghcup install stack --set || true
fi

if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
  if ! "$HOME/.cargo/bin/rustup" show active-toolchain >/dev/null 2>&1; then
    "$HOME/.cargo/bin/rustup" toolchain install stable || true
    "$HOME/.cargo/bin/rustup" default stable || true
  fi
  "$HOME/.cargo/bin/rustup" component add rustfmt clippy rust-analyzer || true
fi

if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.nvm/nvm.sh"
  if [[ ! -s "$HOME/.nvm/alias/default" ]]; then
    nvm install --lts
    nvm alias default 'lts/*'
  fi
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
if command -v claude >/dev/null 2>&1; then
  claude update || warn "Claude Code update failed"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

# Cursor's terminal Agent is independent from the Cursor desktop AppImage.
if command -v agent >/dev/null 2>&1; then
  agent update || warn "Cursor Agent update failed"
else
  curl https://cursor.com/install -fsS | bash
fi

if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  # Bootstrap SDKMAN candidates only when missing. Existing candidate versions
  # remain user-managed and are not advanced by this script.
  set +u
  # shellcheck disable=SC1090
  source "$HOME/.sdkman/bin/sdkman-init.sh"

  [[ -e "$HOME/.sdkman/candidates/java/current" ]] || sdk install java || true
  [[ -e "$HOME/.sdkman/candidates/maven/current" ]] || sdk install maven || true
  [[ -e "$HOME/.sdkman/candidates/gradle/current" ]] || sdk install gradle || true
  [[ -e "$HOME/.sdkman/candidates/quarkus/current" ]] || sdk install quarkus || true

  set -u
fi

log "Installing/updating Lua Language Server"
install_luals() {
  local arch asset tag tmp luals_bin
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64) arch="arm64" ;;
    *) warn "Unsupported architecture for LuaLS binary: $(uname -m)"; return 1 ;;
  esac

  tag="$(curl -fsSL https://api.github.com/repos/LuaLS/lua-language-server/releases/latest | jq -r '.tag_name // empty')"
  [[ -n "$tag" ]] || { warn "Could not determine latest LuaLS release."; return 1; }

  asset="lua-language-server-${tag}-linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  curl -fL "https://github.com/LuaLS/lua-language-server/releases/download/${tag}/${asset}" -o "$tmp/luals.tar.gz"

  rm -rf "$HOME/.local/opt/lua-language-server"
  mkdir -p "$HOME/.local/opt/lua-language-server"
  tar -xzf "$tmp/luals.tar.gz" -C "$HOME/.local/opt/lua-language-server"

  luals_bin="$(find "$HOME/.local/opt/lua-language-server" -type f -name lua-language-server -perm /111 -print -quit)"
  if [[ -z "$luals_bin" ]]; then
    warn "LuaLS archive did not contain an executable lua-language-server."
    rm -rf "$tmp"
    return 1
  fi

  cat > "$HOME/.local/bin/lua-language-server" <<EOF
#!/usr/bin/env bash
exec "$luals_bin" "\$@"
EOF
  chmod +x "$HOME/.local/bin/lua-language-server"

  printf '%s\n' "$tag" > "$HOME/.local/opt/lua-language-server/.version"
  rm -rf "$tmp"

  "$HOME/.local/bin/lua-language-server" --version >/dev/null
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

log "Toolbox convergence complete"
printf '\nUse: toolbox enter %s\nThen start: zsh\n\n' "$DEV_TOOLBOX_NAME"
INNER

log "Installing verification helper"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/verify-dev-toolbox" <<'VERIFY_SCRIPT_EOF'
#!/usr/bin/env bash
set -uo pipefail

BOX="${BOX:-dev}"
VSCODE_FLATPAK="${VSCODE_FLATPAK:-com.visualstudio.code}"

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

check_shell() {
  local name="$1" cmd="$2"
  local output rc
  output="$(timeout --foreground "${CHECK_TIMEOUT}s" zsh -lc 'source "$HOME/.zshrc" >/dev/null 2>&1; eval "$1"' zsh "$cmd" 2>&1)"; rc=$?
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
      env DEV_VERIFY_TMP="$tmp" zsh -lc 'source "$HOME/.zshrc" >/dev/null 2>&1; cd "$DEV_VERIFY_TMP" && eval "$1"' zsh "$cmd" 2>&1
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
  check "JetBrains Toolbox launcher" test -x "$HOME/.local/bin/jetbrains-toolbox"
  check "JetBrains Toolbox binary" test -x "$HOME/.local/opt/jetbrains-toolbox/bin/jetbrains-toolbox"
  check "JetBrains Toolbox version marker" test -s "$HOME/.local/opt/jetbrains-toolbox/.version"
  check "JetBrains Toolbox desktop entry" test -s "$HOME/.local/share/applications/jetbrains-toolbox.desktop"
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

# Match the PATH expected by the managed development shell even though the
# verifier itself runs under bash.
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
check "Oh My Zsh startup" env TERM=dumb zsh -f -c 'source "$HOME/.zshrc" >/dev/null 2>&1; print -r -- OMZ_STARTUP_OK'

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
check_in_tmp "cpanminus module" perl -MApp::cpanminus -e 'print "$App::cpanminus::VERSION\n"'

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
VERIFY_SCRIPT_EOF
chmod +x "$HOME/.local/bin/verify-dev-toolbox"

log "Verifying complete development environment"
if ! "$HOME/.local/bin/verify-dev-toolbox"; then
  echo
  warn "One or more verification checks failed. Paste the complete verification output when asking for a fix."
  exit 1
fi

log "Setup/update complete"
echo "Toolbox: $BOX"
echo "VS Code: $VSCODE_FLATPAK"
echo "JetBrains Toolbox: $HOME/.local/bin/jetbrains-toolbox"
echo "Install JetBrains IDEs from Toolbox after first launch."
echo
echo "For VS Code, start the '$BOX' toolbox and use Dev Containers -> Attach to Running Container."
echo "IntelliJ can directly see SDKMAN/GHCup/rustup files under your shared home; for toolbox-only system tools, use its terminal/toolchain container support where applicable."
