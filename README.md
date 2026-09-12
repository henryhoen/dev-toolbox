# Fedora COSMIC Atomic Dev Toolbox

A reproducible development workstation for **Fedora COSMIC Atomic** built around one flexible Toolbx container (`dev`) while keeping the Atomic host clean.

The project installs a broad programming environment, language/version managers, editors, cloud/database tooling, AI coding assistants, and a verification suite. Setup is intended to be rerunnable: when an upstream package or installer changes, fix the scripts and rerun them instead of repairing the machine by hand.

## Files

| File | Purpose |
|---|---|
| `setup-dev-toolbox.sh` | Initial bootstrap and idempotent repair/setup |
| `update-dev-toolbox.sh` | Updates packages, upstream tools, and manager applications |
| `verify-dev-toolbox.sh` | Verifies the host and complete `dev` environment |
| `AGENTS.md` | Persistent instructions for Codex/AI agents working on this repo |
| `PROJECT_CONTEXT.md` | Design decisions and historical context |

## Architecture

```text
Fedora COSMIC Atomic host
│
├── Podman / Toolbx / Flatpak
│
├── GUI applications
│   ├── Visual Studio Code      Flatpak
│   ├── IntelliJ IDEA          Flatpak
│   └── Cursor                 user-local AppImage
│
└── Toolbx: dev
    ├── zsh + Oh My Zsh
    ├── Neovim
    ├── native build tools
    ├── language ecosystems
    ├── database clients
    ├── Kubernetes/OpenShift tooling
    ├── language servers
    └── AI coding CLIs
```

The host **owns the machine**. The toolbox **owns the development environment**.

## Quick start

Clone the repository on the Fedora Atomic host and run:

```bash
chmod +x setup-dev-toolbox.sh update-dev-toolbox.sh verify-dev-toolbox.sh
./setup-dev-toolbox.sh
```

Do **not** run `setup-dev-toolbox.sh` from inside the `dev` toolbox. It is a host-side orchestration script and will create/use the toolbox itself.

After setup:

```bash
toolbox enter dev
```

The setup script automatically runs verification at the end.

### Testing with a throwaway toolbox

All three scripts honor the `BOX` environment variable. This lets you test against a disposable toolbox without touching the normal `dev` container:

```bash
BOX=dev-test ./setup-dev-toolbox.sh
BOX=dev-test ./verify-dev-toolbox.sh
BOX=dev-test ./update-dev-toolbox.sh
```

The generated `~/.local/bin/dev-shell` helper is bound to the toolbox name used during setup. Remove the throwaway container afterwards with:

```bash
toolbox rm -f dev-test
```

Note that Toolbx shares the host user's home directory, so a throwaway toolbox is fresh for RPM/DNF packages but still sees existing user-level installations such as SDKMAN, nvm, rustup, GHCup, Oh My Zsh, and `~/.local`.

## Updating

Run from the Fedora Atomic host:

```bash
./update-dev-toolbox.sh
```

The updater handles:

- Flatpak application updates
- DNF updates inside `dev`
- Cursor desktop AppImage
- Oh My Zsh
- Lua Language Server
- OpenShift `oc`
- Claude Code
- Cursor Agent
- OpenAI Codex CLI
- GitHub Copilot CLI
- SDKMAN itself
- nvm itself
- rustup itself
- GHCup itself

### What it intentionally does not upgrade

The following SDK/toolchain versions remain under manual user control:

- SDKMAN candidates: Java, Maven, Gradle, Quarkus
- nvm Node.js versions
- rustup Rust toolchains/components
- GHCup GHC/Cabal/HLS/Stack versions

This keeps project/runtime upgrades deliberate while still keeping the manager applications current.

## Verification

Run at any time from the host:

```bash
./verify-dev-toolbox.sh
```

or, after setup has installed the helper:

```bash
verify-dev-toolbox
```

The verifier checks both host-side integration and the complete environment inside `dev`. It deliberately continues after individual failures and prints a complete summary at the end.

Important checks include:

```bash
nvim --version
java --version
mvn --version
gradle --version
quarkus --version
node --version
rustc --version
rust-analyzer --version
ghc --version
cabal --version
haskell-language-server-wrapper --version
go version
zig version
lua-language-server --version
psql --version
kubectl version --client
oc version --client
helm version --short
codex --version
claude --version
agent --version
copilot --version
```

If setup/update fails, paste the **complete script output**, especially the verification summary. The intended maintenance workflow is to fix the repository scripts so rerunning setup repairs the machine.

## Installed development environment

### Shell and terminal tooling

- zsh
- Oh My Zsh
- Neovim
- Git
- GitHub CLI
- curl / wget
- jq / yq
- ripgrep
- fd
- fzf
- direnv
- tmux
- shellcheck
- rsync
- tree

The setup maintains toolbox-specific zsh configuration in:

```text
~/.config/dev-toolbox/zshrc
```

and inserts only a small managed source block into the user's normal `~/.zshrc`.

### C / C++ and native tools

- GCC / G++
- Clang / LLVM / LLD
- Make
- CMake
- Ninja
- GDB
- LLDB
- pkg-config
- common development headers/libraries

### Java / JVM

Managed by **SDKMAN**:

- Java
- Maven
- Gradle
- Quarkus CLI

SDKMAN candidate versions are not automatically advanced by the update script.

### Node.js

Managed by **nvm**. Setup initially installs the current LTS and makes it the default.

The Oh My Zsh nvm plugin is configured for lazy loading.

### Rust

Managed by **rustup**. Setup initially installs stable Rust plus:

- Cargo
- rustfmt
- Clippy
- rust-analyzer

### Haskell

Managed by **GHCup**:

- GHC
- Cabal
- Haskell Language Server
- Stack

For HLS, the expected executable is:

```bash
haskell-language-server-wrapper
```

### Other languages

- Go
- Zig
- Lua + LuaRocks
- Perl + cpanminus
- Erlang + rebar3
- Ruby + RubyGems
- GnuCOBOL
- Common Lisp via SBCL and CLISP
- Guile Scheme
- SWI-Prolog

Lua Language Server is installed from the upstream binary release because it is not assumed to be available as a Fedora package.

## Database tooling

Installed in the toolbox:

- SQLite CLI and development files
- PostgreSQL client/development tooling
  - `psql`
  - `pg_dump`
  - `pg_restore`
  - `libpq-devel`

The PostgreSQL server package is intentionally not required. Run database servers in Podman when needed.

## Kubernetes and OpenShift

The toolbox contains:

- kubectl
- OpenShift `oc`
- Helm

Podman remains host-owned and is used through Toolbx host integration.

## AI coding tools

The environment includes:

- OpenAI Codex CLI
- Claude Code
- Cursor desktop
- Cursor Agent CLI
- GitHub Copilot CLI

Codex and Copilot are installed into the nvm-managed default Node environment. Small wrappers in `~/.local/bin` make them available even before lazy nvm initialization.

Authentication is intentionally left to the user; the setup/verifier should not store API keys or credentials.

## IDEs

### Visual Studio Code

VS Code is installed as a Flatpak. The setup attempts to install the **Dev Containers** extension so VS Code can attach to the running `dev` Toolbx container.

Recommended workflow:

```bash
toolbox enter dev
cd ~/projects/my-project
```

Then attach VS Code to the running `dev` container so language servers and compilers execute in the same environment as the project tooling.

### Cursor

Cursor desktop is installed as a user-local AppImage. Cursor Agent is installed separately inside the toolbox.

Cursor is VS Code-derived and can use a container-attached workflow where supported.

### IntelliJ IDEA

IntelliJ is currently installed as a Flatpak. Toolchains installed beneath the shared home directory (SDKMAN, GHCup, rustup, etc.) are visible as files from both host/user application and toolbox contexts, while DNF-only toolbox binaries may require IntelliJ terminal/container/toolchain integration.

## Oh My Zsh

The configured plugin list should only contain plugins that actually exist in the current Oh My Zsh installation.

Current categories include integrations for:

- Git / Fedora utilities
- Podman
- Kubernetes / OpenShift / Helm
- Maven / Gradle / SDKMAN
- npm / nvm
- Go
- Rust
- Haskell Cabal
- Erlang rebar
- Ruby / gems
- Perl / cpanminus
- PostgreSQL
- rsync / fzf / direnv
- shell quality-of-life plugins

Do not re-add obsolete/nonexistent separate plugins such as `cargo`, `rustup`, `fd`, or `ripgrep` without verifying current upstream support.

## Design principles

1. **Keep Atomic atomic.** Avoid filling the host with layered development RPMs.
2. **One flexible toolbox.** Use `dev` as a full mutable workstation rather than creating a container per command.
3. **Use version managers where they add value.** SDKMAN, nvm, rustup, and GHCup own their ecosystems.
4. **Make failures reproducible.** Fix installation scripts rather than applying undocumented manual repairs.
5. **Test everything important.** Every meaningful installed tool should have a non-interactive verifier check.
6. **Preserve user configuration.** Managed zsh snippets must not destroy unrelated dotfiles.
7. **Prefer trustworthy sources.** Fedora repositories and official upstream installers/releases come before third-party packaging.

## Continuing development with Codex

Codex automatically uses repository `AGENTS.md` instructions as project guidance. `AGENTS.md` applies to the directory tree beneath it.

After adding `AGENTS.md` and `PROJECT_CONTEXT.md` to the repository, a useful first Codex prompt is:

```text
Read AGENTS.md, README.MD, and PROJECT_CONTEXT.md, then inspect the three shell scripts.
This repository configures my Fedora COSMIC Atomic development toolbox.
Continue from that context. When I paste setup/update/verification failures, fix the scripts so rerunning setup repairs the environment rather than giving me one-off manual fixes.
```

The repository keeps `AGENTS.md` concise and uses it as a map to deeper project documentation, while the longer historical/design context lives in `PROJECT_CONTEXT.md`.
