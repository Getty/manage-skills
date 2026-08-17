# CLAUDE.md

Guidance for Claude Code working in this repository. Product documentation lives in
[README.md](README.md).

## What This Is

`manage-skills` — one self-contained bash script that hardlinks skill files between
projects so every copy shares a single inode. No build step, no dependencies.

- Command surface: `./manage-skills --help`
- Tests: `bash test/smoke-test.sh`
- Syntax: `bash -n manage-skills`

## Editing skills — keep the inode

`.claude/skills/manage-skills/SKILL.md` is the **source of truth** that other projects
hardlink against. `Edit` and `Write` rewrite-and-replace: the path gets a fresh inode,
and every other project silently keeps the old content.

Edit hardlinked files with a shell redirect, which truncates in place:

```bash
cat > .claude/skills/<skill>/SKILL.md <<'SKILL'
…
SKILL
stat -c '%i %h' .claude/skills/<skill>/SKILL.md   # inode and link count must match the pre-edit values
```

`cp new old` is equally safe. `sed -i` renames on GNU — treat it as unsafe here. Full
rules and the repair recipe live in that skill file.

## Shell constraints

`set -euo pipefail` is enforced. Three traps follow from it and from the platform floor:

**A pipeline inside an assignment aborts the script.** `x=$(echo "$list" | grep foo | cut -d: -f1)`
dies when `grep` matches nothing: `pipefail` propagates its exit 1 and `set -e` acts on
it. This shipped as a bug — `check` died in every project that owned a skill of its own,
leaving its `originals` branch unreachable. Match with a `case` inside a `while read`
loop instead, as `cmd_check` now does.

**Bash 3.2 is the floor** (the system bash on macOS). Index arrays, `while read`, and
C-style `for ((…))` carry everything here; `declare -A`, `mapfile`, and `readarray` are
4.x-only. `&>` is fine — 3.2 has it, and the script and installer both use it. Verify
against `/bin/bash` and a Homebrew bash 5.x.

**`stat` argument order matters**: `stat -c %i` first, `stat -f %i` as the fallback.
Reversed, GNU reads `%i` as a filename, prints filesystem info to stdout and exits 1 —
the fallback then appends the real inode to that garbage and every comparison fails.
That reversal in the smoke test kept the Linux CI red from the very first run.

## Rendering

**Visible width is not string length.** Rendered cells carry ANSI escapes and a
multibyte `●`, both of which `${#var}` and `printf %-30s` miscount. `print_grid` takes
the visible width as an explicit field per row — compute it from the plain skill name,
never from the rendered string.

**Every listing has two modes**: columns on a terminal (`[[ -t 1 ]]`), one record per
line when piped. Keep the piped shape stable — `grep`/`awk` pipelines and the smoke
tests read it.

## Config

`~/.manage-skills/` holds `sources`, `targets`, and an optional `notes.md`.
`MANAGE_SKILLS_HOME` overrides the directory and the smoke tests depend on that, so
derive every path from `CONFIG_DIR`. `ensure_config` repairs a partial config (directory
present, files missing) rather than assuming an existing directory is complete.

**Derive, don't restate.** `locations` renders the source inventory from `sources` plus a
directory scan, so nothing hand-maintained can go stale against it. A `sources` line's
trailing `# label` is the one piece a scan cannot recover; free-form context that is not
derivable at all goes in `notes.md`, which `locations` appends verbatim. Reach for one of
those two before adding a new config file.

A source line is `path` plus an optional trailing `# label` — `parse_source_line` splits
it and every reader goes through `read_source_lines`. A source path containing a literal
`#` would be truncated at it; no other input changes meaning under this format.

## Packaging

The repo is three things at once, from one set of files:

- **CLI** — `manage-skills`, installed by `install.sh` or Homebrew.
- **Claude Code plugin** — `.claude-plugin/plugin.json` points `skills` at
  `./.claude/skills`, so the shipped skills stay where the repo already keeps them
  instead of being duplicated into `skills/`. `bin/manage-skills` is a *relative* symlink
  to the script; the plugin's `bin/` goes on the Bash tool's `PATH`, so installing the
  plugin is enough to get the command. A relative symlink survives a clone — the absolute
  kind is exactly what this tool exists to avoid.
- **Marketplace** — `.claude-plugin/marketplace.json` lists this repo as its own plugin
  (`"source": "./"`).

Validate both manifests with `claude plugin validate . --strict`.

Two hand-maintained lists have to track reality, and the smoke tests fail if they drift:
`SELF_SKILLS` in the script must match the directories in `.claude/skills/`, and the
version must be identical in the script, `plugin.json`, and `marketplace.json`.

`cmd_self` resolves its own location by walking `BASH_SOURCE` through symlinks — `$0`'s
directory is the bin dir, not the checkout, whenever `install.sh` ran in dev mode. How it
updates depends on how it was installed: a checkout says "git pull", a plugin says
"/plugin update", only a standalone copy rewrites itself. That rewrite `exec`s a separate
shell to overwrite the file, so the running bash never reads a file that is changing
underneath it.

## CI and releases

CI runs the smoke tests on `ubuntu-latest` and `macos-latest`. GNU/BSD divergence is the
usual break; a change that passes on only one platform is not done.

Commits are conventional (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`) and always
`--signoff`. Merging to `main` cuts a SemVer release from those prefixes, and the release
job rewrites the version in the script and both manifests to match the new tag — leave
those three lines to the workflow.
