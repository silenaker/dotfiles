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

Uses **symlinks** so dotfiles stay in sync with the mounted repo.

## Adding a new dotfile

1. Add the dotfile (e.g. `.bashrc`) to the repo root.
2. Write a merge function in `lib/merge-<name>.sh`.
3. Write unit tests in `test/test-merge-<name>.sh`.
4. Wire it into `build.sh` (add the `emit_file` call + orchestration).
5. Run `./build.sh` then `./test/test.sh`.

## Build & test

```bash
./build.sh              # assemble
./test/test.sh          # unit + integration
```
