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

**`local a=$1 b=$a` breaks under `set -u`.** Bash declares every name in a `local`
statement first and assigns afterwards, so the second reads an unset variable and the
script dies. Split them onto separate `local` lines when one derives from another.

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

## Remote sources

A remote source is stored twice, and that is the whole point:

- `cache/<name>/` — the git checkout, pure transport.
- `sources.d/<name>/` — the files projects hardlink against.

`update` pulls the cache, then copies changed files across with `cat >`, which truncates
in place and keeps the inode. Every project linked to that file therefore has the new
content the moment `update` finishes — no per-project `sync`, no registry of which
projects use which source. Pulling straight into the linked copy would rename-and-replace
and strand every hardlink on the old content, which is precisely the drift this tool
exists to prevent.

Two consequences worth preserving: files that vanish upstream are reported, never
deleted, because a project may still hold a hardlink to one; and `remote_behind` compares
`HEAD` against the already-fetched upstream ref, so `list` and `locations` can show
"updates available" without a network round-trip. Fetching belongs to `update`.

The skill directory inside a checkout is detected (`skills/`, `.claude/skills/`, root),
not configured — asking a user which layout a repo uses is asking them to go look.

## Three routes, one set of files

Claude Code and Codex both lay skills out as `<name>/SKILL.md`. Only the surroundings
differ, and that is what makes one directory serve everyone:

| | Claude Code | Codex |
|---|---|---|
| Plugin manifest | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` |
| Marketplace manifest | `.claude-plugin/marketplace.json` | `.agents/plugins/marketplace.json` |
| Project skills | `.claude/skills/` | `.agents/skills/` |
| Install | `/plugin install x@mp` | `codex plugin add x@mp` |

`package` writes both plugin manifests with a `skills` path pointing at wherever the
directories already sit — nothing is copied — and prints both marketplace entries plus
the `sources add` line. The default targets cover both project paths.

Which route fits whom is the thing to keep straight when touching this code. A plugin
install is one line and needs no new tooling, so it wins for someone who just wants the
skills on their machine. A hardlink puts the skill *in the repo*, so it reaches teammates
on clone, can be chosen per project, and works with neither CLI installed. None of them
replaces the others, and `package` never picks — it prints all three.

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

The repo is two things at once, from one set of files:

- **CLI** — `manage-skills`, installed by `install.sh` or Homebrew.
- **Claude Code plugin** — `.claude-plugin/plugin.json` points `skills` at
  `./.claude/skills`, so the shipped skills stay where the repo already keeps them
  instead of being duplicated into `skills/`. `bin/manage-skills` is a *relative* symlink
  to the script; the plugin's `bin/` goes on the Bash tool's `PATH`, so installing the
  plugin is enough to get the command. A relative symlink survives a clone — the absolute
  kind is exactly what this tool exists to avoid.

Distribution goes through the shared catalog at
[Getty/claude-code](https://github.com/Getty/claude-code), which lists this repo as a
github source. This repo carries no `marketplace.json` of its own — one catalog for every
plugin, so users register a single marketplace.

Validate the manifest with `claude plugin validate .`. It warns that a root `CLAUDE.md`
is not loaded as project context — expected here, because this file is guidance for
working *on* manage-skills, not content the plugin ships. That warning is why `--strict`
fails; use the plain form.

Two hand-maintained lists have to track reality, and the smoke tests fail if they drift:
`SELF_SKILLS` in the script must match the directories in `.claude/skills/`, and the
version must be identical in the script and `plugin.json`.

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
job rewrites the version in the script and in `plugin.json` to match the new tag — leave
those two lines to the workflow.
