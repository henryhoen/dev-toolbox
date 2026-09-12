# Codex instructions

This repository manages a reproducible Fedora COSMIC Atomic development workstation based on one long-lived Toolbx container named `dev`.

Before changing anything, read:

1. `README.MD`
2. `PROJECT_CONTEXT.md`
3. The three lifecycle shell scripts in this repository

## Repository files

- `setup-dev-toolbox.sh` — single host-side lifecycle command. Installs, updates, and repairs/converges the Toolbx environment and host GUI applications without upgrading manager-controlled SDK/toolchain versions after bootstrap.
- `verify-dev-toolbox.sh` — verification suite. Tests host integration and every important tool inside `dev` and prints all failures before exiting non-zero.
- `cleanup-dev-toolbox.sh` — destructive host-side cleanup used for true clean reinstall testing. Removes the selected toolbox plus the user-level state this project manages so setup can be tested from scratch.

## Required behavior

- These scripts target Fedora COSMIC Atomic. Do not turn the host into a traditional mutable workstation with broad `rpm-ostree` package layering.
- `setup-dev-toolbox.sh` and `cleanup-dev-toolbox.sh` are launched from the Fedora Atomic host, not from inside Toolbx.
- Development CLI tools belong in Toolbx unless there is a strong host-specific reason.
- GUI IDE/editors belong on the host/user application layer. Current design uses Flatpak for VS Code, a user-local official JetBrains Toolbox tarball for JetBrains IDEs, and a user-local AppImage for Cursor. JetBrains IDEs are managed by Toolbox on the host, not installed inside Toolbx.
- Keep the setup script idempotent and safe to rerun on an already-configured machine.
- Prefer official upstream installers/repos or Fedora packages. Do not introduce random COPR repositories unless specifically requested.
- Keep `$HOME` sharing between the host and Toolbx in mind. Do not use `chsh` to change the user's host login shell merely to configure the toolbox.
- Oh My Zsh configuration is managed via `~/.config/dev-toolbox/zshrc`, with a small sourced block in `~/.zshrc`. Do not overwrite unrelated user `.zshrc` content.
- Verify that any Oh My Zsh plugin added to the configuration actually exists in the current Oh My Zsh tree. Plugins removed upstream must not be listed.

## Version-management policy

The user prefers flexible language version managers.

Manager-owned SDK/toolchain versions are **user-managed** after the initial bootstrap:

- SDKMAN: Java, Maven, Gradle, Quarkus
- nvm: Node.js/npm runtime versions
- rustup: Rust toolchains/components
- GHCup: GHC, Cabal, HLS, Stack

`setup-dev-toolbox.sh` may update the **manager programs themselves**, but must not automatically advance those managed SDK/toolchain versions after the initial bootstrap.

Examples:

- Allowed: `sdk selfupdate`, SDKMAN metadata refresh
- Not allowed: `sdk upgrade`
- Allowed: update nvm itself
- Not allowed: install a newer Node runtime automatically
- Allowed: update rustup itself
- Not allowed: `rustup update` of toolchains
- Allowed: `ghcup upgrade`
- Not allowed: silently switch to newer GHC/HLS/Stack versions

Manually downloaded tools such as JetBrains Toolbox, Lua Language Server, OpenShift `oc`, Cursor desktop, Claude Code, Cursor Agent, Codex CLI, and GitHub Copilot CLI should be updated by `setup-dev-toolbox.sh` when practical.

## Testing requirements

After changing any script:

1. Run `bash -n` on all three lifecycle shell scripts.
2. Run `shellcheck` when available and address actionable findings without adding pointless suppressions.
3. If working on a Fedora Atomic machine with Toolbx available, run `./verify-dev-toolbox.sh` after changes that can be tested locally.
4. Verification must continue through all checks and report all failures, not abort on the first missing tool.
5. Any newly installed important tool must receive a non-interactive verification check, normally a `--version` command.

Examples already important to preserve:

```bash
haskell-language-server-wrapper --version
lua-language-server --version
codex --version
claude --version
agent --version
copilot --version
```

When a user provides failed setup/update/verifier output, diagnose the actual cause, patch the scripts so a clean/rerun installation handles the problem automatically, and update the verifier if the failure exposed a missing check.

## Cleanup and clean-install testing

- Keep `cleanup-dev-toolbox.sh` aligned with everything setup creates. If setup begins creating a new managed file, user-level installation, Flatpak, AppImage, wrapper, or config directory, decide whether cleanup must remove it and update cleanup in the same change.
- Cleanup must honor `BOX`, be safe to rerun, and require explicit confirmation unless `--yes` is supplied.
- Cleanup is intentionally destructive to project-managed development state. Do not broaden it to unrelated user files or unrelated Flatpaks.
- Cleanup must remove JetBrains Toolbox and `~/.local/share/JetBrains/Toolbox` so IDEs installed through Toolbox are also removed during a complete clean reinstall test.
- A full acceptance test is: cleanup -> setup -> verify. Capture logs when debugging failures.
- When a clean-install failure is reported, patch setup/update/verify/cleanup as needed so the repository remains internally consistent.

## Shell style

- Bash scripts use `#!/usr/bin/env bash`.
- Setup scripts should use `set -Eeuo pipefail` unless a deliberate reason requires otherwise.
- Quote variables.
- Prefer functions for non-trivial install/update blocks.
- Use clear `log`/`warn` output.
- Network or package failures that are optional/release-dependent may warn and continue, but essential environment failures should fail clearly.
- Avoid hard-coded usernames or home paths; use `$HOME`.
- Support x86_64 first and aarch64 where upstream binaries are readily available.

## Documentation policy

When behavior, installed tooling, update policy, requirements, or commands change, update `README.MD` and `PROJECT_CONTEXT.md` as appropriate in the same change.

Do not claim a package exists in Fedora or a current upstream install/update command works without checking when that fact is uncertain or time-sensitive.
