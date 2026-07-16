# dotfiles

Dotfiles — one command to bootstrap your $HOME.

## Install

Two installers for different scenarios.

### `bootstrap.sh` — any Linux / WSL (one-liner)

Self-contained, no clone needed. **Merges** dotfiles into `$HOME` — never overwrites your settings.

```bash
curl -sSf https://raw.githubusercontent.com/silenaker/dotfiles/main/bootstrap.sh | bash
```

### `install.sh` — DevContainer dotfiles

Executed automatically by DevContainer tools (e.g. VS Code Dev Containers extension,
GitHub Codespaces). Configure your DevContainer tools to point at this repo — the tool
clones it and runs `install.sh` on container start.

## Adding a new dotfile

Two paths, depending on the installer.

### For `bootstrap.sh` (curl-pipe-bash)

1. Add the dotfile to the repo root.
2. Write a merge function in `lib/merge-<name>.sh`.
3. Write unit tests in `test/test-merge-<name>.sh`.
4. Wire it into `build.sh` (add the `emit_file` call + orchestration).
5. Run `./build.sh` then `./test/test.sh`.

### For `install.sh` (DevContainer)

Add the install logic directly to `install.sh`. Prefer reference-based approaches
(e.g. `source` for shell scripts, `include.path` for git config).
Fall back to symlinks or copying only when the dotfiles don't support
an reference/include/import mechanism.

## Build & test

```bash
./build.sh              # assemble
./test/test.sh          # unit + integration
```
