# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

manage-skills — hardlink-based skill sharing across AI coding tool projects. See [README.md](README.md) for full documentation.

## Build & Run

```bash
./manage-skills --help       # show usage
./manage-skills --version    # show version
./manage-skills list         # list available skills in current project
./manage-skills link <name>  # hardlink a skill into current project
./manage-skills check        # verify hardlink integrity
./manage-skills sync         # re-hardlink stale copies
```

Install via `./install.sh` or Homebrew (`brew install Getty/manage-skills/manage-skills`).

## Testing

```bash
bash test/smoke-test.sh      # run smoke tests
bash -n manage-skills        # syntax check
```

## Key Conventions

- **Single-file tool**: `manage-skills` is one self-contained bash script — no build step.
- **Shell compatibility**: must run on bash 3.2+ (macOS system bash). No associative arrays (`declare -A`), no `readarray`/`mapfile`, no `&>` redirects in new code. Test with both `/bin/bash` (3.2) and Homebrew bash (5.x).
- **`set -euo pipefail`** is enforced. Preserve this.
- **Config lives in** `~/.manage-skills/` (sources, targets files). `MANAGE_SKILLS_HOME` overrides the location.
- **Hardlinks, not symlinks**: the core mechanism uses `ln` (not `ln -s`) so skill files share inodes with their source.
- **`stat` portability**: GNU (`stat -c %i`) and BSD (`stat -f %i`) are both handled — keep the fallback pattern.
- **Commits** use conventional commit style (`feat:`, `fix:`, `docs:`, `test:`, `ci:`). Always `--signoff`.
- **Versioning** follows SemVer. Releases are cut automatically on merge to `main` based on conventional commit prefixes.
