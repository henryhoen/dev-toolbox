# Project context

## Goal

Build and maintain a flexible programming workstation on **Fedora COSMIC Atomic** while keeping the Atomic host clean.

The central model is:

```text
Fedora COSMIC Atomic host
├── Toolbx / Podman / Flatpak and host integration
├── GUI development applications
│   ├── Visual Studio Code (Flatpak)
│   ├── JetBrains Toolbox (user-local tarball)
│   │   └── JetBrains IDEs (managed by Toolbox)
│   └── Cursor (user-local AppImage)
└── Toolbx: dev
    └── mutable programming environment
```

The user prefers a broad, long-lived toolbox rather than one toolbox per language/tool. Language version managers provide version flexibility inside that environment.

## Scripts

### setup-dev-toolbox.sh

JetBrains Toolbox is host-owned and setup creates a user desktop entry so COSMIC application search can launch it.

Run from the host.

Responsibilities:

- Ensure Flathub exists for the current user.
- Install VS Code as a Flatpak.
- Install JetBrains Toolbox as a user-local host application; JetBrains IDEs are installed interactively through Toolbox.
- Install/update Cursor desktop as a user-local AppImage.
- Create Toolbx container `dev` if missing.
- Install Fedora development packages in the toolbox.
- Install Kubernetes/OpenShift tooling.
- Install Oh My Zsh and configure useful plugins.
- Install SDKMAN, nvm, rustup, and GHCup.
- Perform initial managed-tool installations.
- Install LuaLS manually from upstream.
- Install AI coding CLIs.
- Install/write the verifier.
- Run verification at the end.

The script should be safe to rerun and acts as install + update + repair/convergence.

The setup script is also the updater: rerunning it upgrades managed infrastructure and repairs drift while leaving manager-controlled SDK/toolchain versions unchanged after bootstrap.

### cleanup-dev-toolbox.sh

Run from the host.

Responsibilities:

- Remove the selected Toolbx container (`dev` by default, configurable with `BOX`).
- Remove project-managed shared-home state so a subsequent setup is a true first-install test.
- Remove Oh My Zsh, SDKMAN, nvm, rustup/Cargo, GHCup, LuaLS, generated helpers/configuration, AI-tool wrappers/installations, and Cursor user-local artifacts created by this project.
- Remove the VS Code Flatpak installed by this project.
- Remove JetBrains Toolbox, its managed IDE/application tree, and JetBrains config/cache for the complete-clean-test workflow.
- Remove `~/.zshrc` for the complete-clean-test workflow so setup must recreate it.
- Require explicit confirmation unless `--yes` is provided.
- Be idempotent and verify cleanup at the end.

The cleanup script is part of the normal maintenance contract: when setup starts managing new persistent host/home state, cleanup should be updated in the same change.

### verify-dev-toolbox.sh

May be invoked from the host. It dispatches into `dev` and tests host + toolbox state.

The verifier intentionally collects all failures before returning non-zero. Full output is designed to be pasted into Codex/ChatGPT for diagnosis.

## Full acceptance test

The strongest regression test for this repository is:

```bash
./cleanup-dev-toolbox.sh --yes
./setup-dev-toolbox.sh 2>&1 | tee setup-full-test.log
./verify-dev-toolbox.sh 2>&1 | tee verify-full-test.log
```

This is preferred before handing major changes off because Toolbx shares `$HOME`; merely creating another toolbox is not a complete first-install test for SDKMAN, nvm, rustup, GHCup, Oh My Zsh, LuaLS, or other user-level state.

## Tooling currently intended

### Shell/editor/general CLI

- zsh
- Oh My Zsh
- Neovim
- Git
- GitHub CLI (`gh`)
- curl/wget
- jq/yq
- ripgrep
- fd
- fzf
- direnv
- tmux
- shellcheck
- rsync
- tree
- common Unix/network diagnostic tools

### Native development

- GCC/G++
- Clang/LLVM/LLD
- Make
- CMake
- Ninja
- GDB
- LLDB
- pkg-config and common development libraries

### Java/JVM

Managed by SDKMAN after bootstrap:

- Java
- Maven
- Gradle
- Quarkus CLI

### JavaScript/Node

Managed by nvm after bootstrap:

- Node.js LTS initially
- npm follows Node

### Rust

Managed by rustup after bootstrap:

- stable Rust initially
- cargo
- rustfmt
- clippy
- rust-analyzer

### Haskell

Managed by GHCup after bootstrap:

- GHC
- Cabal
- Haskell Language Server
- Stack

The HLS verification command is deliberately:

```bash
haskell-language-server-wrapper --version
```

not `haskell-language-server --version`.

### Other languages

- Go
- Zig
- Lua + LuaRocks
- Lua Language Server (manual upstream install)
- Perl + cpanminus
- Erlang + rebar3
- Ruby + RubyGems
- GnuCOBOL
- Common Lisp: SBCL and CLISP
- Scheme: Guile
- Prolog: SWI-Prolog

### Databases

Client/development tooling only:

- SQLite (`sqlite3`, development headers)
- PostgreSQL client tools (`psql`, `pg_dump`, `pg_restore`) and `libpq-devel`

Do not install `postgresql-server` merely to obtain PostgreSQL client tools. Database servers are better run through Podman when needed.

### Containers/cloud

- Podman stays host-owned but should be usable from Toolbx integration.
- kubectl
- OpenShift `oc`
- Helm

### AI coding tools

- OpenAI Codex CLI
- Claude Code
- Cursor Agent CLI
- GitHub Copilot CLI
- Cursor desktop editor

Codex and Copilot are currently installed through the nvm-managed default Node environment. The scripts provide wrappers under `~/.local/bin` so they remain usable when nvm is lazy-loaded by Oh My Zsh.

## Oh My Zsh decisions

The current desired plugin set is centered on tools actually present and supported by current Oh My Zsh.

Important historical correction: `cargo`, `rustup`, `fd`, and `ripgrep` were previously suggested as separate plugins but do not exist in the current installation. Rust integration is handled by the `rust` plugin and fd/ripgrep work without dedicated OMZ plugins.

The nvm plugin initializes nvm and is configured for lazy loading. SDKMAN still needs its initialization script sourced; the `sdk` plugin alone is not a replacement for SDKMAN initialization.

## Host versus toolbox policy

Host-owned examples:

- Podman
- Toolbx
- Flatpak
- rpm-ostree / bootc / host system management
- GUI IDE/editors, including JetBrains Toolbox-managed IDEs

Toolbox-owned examples:

- compilers
- language CLIs
- build tools
- Neovim
- zsh environment
- Git/dev CLI tools
- kubectl/oc/Helm
- database clients
- language servers
- AI terminal agents

Duplicating a development tool inside Toolbx even when Fedora Atomic already exposes a host copy is acceptable and often preferred. The toolbox should be a self-contained development workstation rather than accidentally depending on host package versions.

## Failure-handling philosophy

The repository exists partly so the environment never has to be rebuilt manually.

When setup fails:

1. User runs/pastes setup or verifier output.
2. Diagnose the precise Fedora/upstream mismatch.
3. Fix the script, not just the current machine.
4. Add or improve a verifier check if useful.
5. Preserve rerun safety so executing setup again repairs the environment.

Known examples that motivated this policy:

- Fedora did not provide `lua-language-server` as a DNF package, so LuaLS moved to an upstream binary install.
- Fedora did not provide `haskell-language-server`, so Haskell tooling moved to GHCup.
- HLS exposes `haskell-language-server-wrapper`, which is the command the verifier must check.
- Several previously assumed Oh My Zsh plugins no longer existed upstream and were removed.

## Expected interaction with Codex

When continuing work in Codex, a typical request can simply be:

> Read AGENTS.md and PROJECT_CONTEXT.md, inspect the current scripts, then continue maintaining this Fedora COSMIC Atomic dev-toolbox project. If I paste installer/verifier output, fix the scripts so rerunning setup resolves the issue and extend verification when appropriate.
