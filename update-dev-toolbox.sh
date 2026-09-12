#!/usr/bin/env bash
set -Eeuo pipefail

BOX="${BOX:-dev}"
VSCODE_FLATPAK="${VSCODE_FLATPAK:-com.visualstudio.code}"
IDEA_FLATPAK="${IDEA_FLATPAK:-com.jetbrains.IntelliJ-IDEA-Ultimate}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }

if [[ -f /run/.toolboxenv ]]; then
  echo "Run this update script on the Fedora Atomic host." >&2
  exit 1
fi

log "Updating Flatpak applications"
flatpak update --user -y

log "Updating Cursor desktop AppImage"
update_cursor_desktop() {
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
  else
    warn "Cursor desktop update failed; existing AppImage was left untouched"
  fi
  rm -f "$tmp"
}
update_cursor_desktop

log "Updating toolbox DNF packages and user-managed infrastructure"
toolbox run --container "$BOX" bash -s <<'INNER'
set -Eeuo pipefail
log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }

log "DNF upgrade"
sudo dnf upgrade --refresh -y
sudo dnf autoremove -y || true

log "Oh My Zsh update"
if [[ -x "$HOME/.oh-my-zsh/tools/upgrade.sh" ]]; then
  ZSH="$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh/tools/upgrade.sh" || warn "Oh My Zsh update failed"
fi

log "SDKMAN manager + candidate metadata update (installed SDKs are NOT upgraded)"
if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  sdk selfupdate || warn "SDKMAN self-update failed"
  sdk update || warn "SDKMAN metadata update failed"
fi

log "nvm manager update (Node versions are NOT upgraded)"
if [[ -d "$HOME/.nvm" ]]; then
  NVM_TAG="$(curl -fsSLI https://github.com/nvm-sh/nvm/releases/latest | awk -F/ 'tolower($1)=="location:" {gsub("\\r",""); print $NF}' | tail -1)"
  if [[ -n "$NVM_TAG" ]]; then
    PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh | bash" || warn "nvm update failed"
  else
    warn "Could not determine latest nvm release"
  fi
fi

log "Updating AI coding CLIs"
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.nvm/nvm.sh"
  nvm use default >/dev/null 2>&1 || true
  if command -v npm >/dev/null 2>&1; then
    npm install -g @openai/codex@latest @github/copilot@latest || warn "Codex/Copilot CLI update failed"
  fi
fi
if command -v claude >/dev/null 2>&1; then
  claude update || warn "Claude Code update failed"
else
  curl -fsSL https://claude.ai/install.sh | bash || warn "Claude Code installation failed"
fi
if command -v agent >/dev/null 2>&1; then
  agent update || warn "Cursor Agent update failed"
else
  curl https://cursor.com/install -fsS | bash || warn "Cursor Agent installation failed"
fi

log "rustup manager update (Rust toolchains are NOT upgraded)"
if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
  "$HOME/.cargo/bin/rustup" self update || warn "rustup self-update failed"
fi

log "GHCup manager update (GHC/Cabal/HLS/Stack versions are NOT upgraded)"
if [[ -x "$HOME/.ghcup/bin/ghcup" ]]; then
  "$HOME/.ghcup/bin/ghcup" upgrade || warn "GHCup update failed"
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/opt"

log "Lua Language Server update"
update_luals() {
  local arch latest current asset tmp luals_bin
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64) arch="arm64" ;;
    *) warn "Unsupported LuaLS architecture: $(uname -m)"; return 1 ;;
  esac

  latest="$(curl -fsSL https://api.github.com/repos/LuaLS/lua-language-server/releases/latest | jq -r '.tag_name // empty')"
  current="$(cat "$HOME/.local/opt/lua-language-server/.version" 2>/dev/null || true)"
  [[ -n "$latest" ]] || { warn "Could not determine latest LuaLS release"; return 1; }

  if [[ "$latest" == "$current" && -x "$HOME/.local/bin/lua-language-server" ]]; then
    echo "LuaLS already current: $current"
    return 0
  fi

  asset="lua-language-server-${latest}-linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  curl -fL "https://github.com/LuaLS/lua-language-server/releases/download/${latest}/${asset}" -o "$tmp/luals.tar.gz"

  rm -rf "$HOME/.local/opt/lua-language-server"
  mkdir -p "$HOME/.local/opt/lua-language-server"
  tar -xzf "$tmp/luals.tar.gz" -C "$HOME/.local/opt/lua-language-server"

  luals_bin="$(find "$HOME/.local/opt/lua-language-server" -type f -name lua-language-server -perm /111 -print -quit)"
  [[ -n "$luals_bin" ]] || { rm -rf "$tmp"; warn "LuaLS executable not found after extraction"; return 1; }

  cat > "$HOME/.local/bin/lua-language-server" <<EOF
#!/usr/bin/env bash
exec "$luals_bin" "\$@"
EOF
  chmod +x "$HOME/.local/bin/lua-language-server"

  printf '%s\n' "$latest" > "$HOME/.local/opt/lua-language-server/.version"
  rm -rf "$tmp"
  "$HOME/.local/bin/lua-language-server" --version >/dev/null
  echo "LuaLS updated to $latest"
}
update_luals

log "OpenShift oc client update"
update_oc() {
  local arch url tmp
  case "$(uname -m)" in
    x86_64) arch="linux" ;;
    aarch64) arch="linux-arm64" ;;
    *) warn "Unsupported oc architecture: $(uname -m)"; return 0 ;;
  esac

  url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  if curl -fL "$url" -o "$tmp/oc.tar.gz"; then
    tar -xzf "$tmp/oc.tar.gz" -C "$tmp"
    install -m 0755 "$tmp/oc" "$HOME/.local/bin/oc"
    "$HOME/.local/bin/oc" version --client 2>/dev/null || true
  else
    warn "oc update failed; current binary was left untouched"
  fi
  rm -rf "$tmp"
}
update_oc

log "Update complete"
echo "Managed SDK/tool versions were intentionally left alone:"
echo "  SDKMAN candidates (Java/Maven/Gradle/Quarkus)"
echo "  nvm Node versions"
echo "  rustup Rust toolchains/components"
echo "  GHCup GHC/Cabal/HLS/Stack versions"
INNER


log "Running post-update verification"
if [[ -x "$HOME/.local/bin/verify-dev-toolbox" ]]; then
  if ! "$HOME/.local/bin/verify-dev-toolbox"; then
    warn "Update finished, but one or more verification checks failed. Paste the complete output when asking for a fix."
    exit 1
  fi
else
  warn "Verification helper is not installed. Re-run setup-dev-toolbox.sh once to install it."
fi
