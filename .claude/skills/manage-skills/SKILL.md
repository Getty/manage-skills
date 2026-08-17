---
name: manage-skills
description: "manage-skills CLI — hardlink-based skill sharing across AI coding tool projects. Use when adding, removing, syncing, editing, or checking shared skills, when asking where a skill comes from, or before editing any hardlinked SKILL.md."
user-invocable: true
---

# manage-skills — Hardlink-Based Skill Sharing

CLI tool for managing shared skill files across projects via hardlinks. Config lives in `~/.manage-skills/`.

> **⚠️ Editing a linked SKILL.md? Use `cat > file` — NOT the `Edit`/`Write` tools.**
> They rewrite-and-replace → new inode → silently breaks the hardlink to every other
> project sharing that file. Full rules + repair in
> [Editing hardlinked skills](#editing-hardlinked-skills--do-not-break-the-inode) below.

## Commands

```bash
manage-skills                        # Interactive mode (fzf or numbered menu)
manage-skills list                   # Show all skills with status
manage-skills locations              # Where skills come from, per source
manage-skills link <skill>...        # Hardlink skills into current project
manage-skills unlink <skill>...      # Remove skills from current project
manage-skills sync                   # Re-hardlink stale copies
manage-skills update [name...]       # Pull remote sources (--check only reports)
manage-skills package [dir]          # Make a skill directory installable by others
manage-skills check                  # Verify hardlink integrity
manage-skills sources                # List source directories
manage-skills sources add <dir|repo> [label]  # Add a source, local or remote
manage-skills sources remove <dir>   # Remove a skill source
manage-skills targets                # List configured targets
manage-skills targets add <n> <p> <f> # Add target (name:path:file)
manage-skills self                   # Where this install and its own skills live
manage-skills self install           # Register the shipped skills as a source
manage-skills self update            # Update the script and the shipped skills
manage-skills init                   # Create ~/.manage-skills/ config
```

Every command takes `--target <name>` (default: `claude`).

## Status Icons

- `[*]` — hardlinked from source (in sync)
- `[~]` — local copy, not a hardlink (drifted)
- `[ ]` — available but not linked
- `●` — original, this project is the source of truth

On a terminal, `list` and `locations` group skills by source and lay each group out in
columns. Piped output stays one skill per line, so `manage-skills list | grep …` works.

## Where skills live — ask the tool, don't keep a list

`manage-skills locations` renders the whole picture from config and disk: every source
with its label and the skills it provides, the skills the current project owns outright,
and any name **shadowed** by an earlier source (marked `*` — that copy never wins a link
or a sync, which is a common silent drift cause).

A hand-maintained inventory of the same thing goes stale the first time a skill moves.
The three things that genuinely can't be derived — naming conventions, which skills pair
up, which ones are conditional — belong in `~/.manage-skills/notes.md`, which `locations`
prints at the end.

## This tool ships its own skills

`manage-skills` and `manage-skills-drift-triage` come with the tool.
`manage-skills self install` registers them as a (lowest-priority) source, so they link
like anything else. `manage-skills self` shows where they are and whether they're
registered; `manage-skills self update` refreshes them.

Installing the Claude Code plugin does the same thing a different way — it puts the CLI
on `PATH` and loads both skills:

```
/plugin marketplace add Getty/claude-code
/plugin install manage-skills@getty
```

## Remote sources

A source can be a repository instead of a directory:

```bash
manage-skills sources add github:Getty/perl-skills Shared Perl ecosystem
manage-skills update --check   # anything new upstream?
manage-skills update           # fetch it
```

`update` writes changed files **in place**, so the inode survives and every project
already linked to that skill has the new content the moment it finishes. Never run a
per-project `sync` after an update — there is nothing to fix. A skill that disappears
upstream is reported, never deleted, because a project may still be linked to it.

Stored in two places on purpose: `~/.manage-skills/cache/<name>/` is the git checkout,
`~/.manage-skills/sources.d/<name>/` holds the files that get hardlinked. Pulling
straight into the linked copy would rename-and-replace and strand every hardlink — the
drift this tool exists to prevent.

## Publishing a skill set

`manage-skills package <dir>` writes `.claude-plugin/plugin.json` pointing at the skill
directories where they already are — no copying — and prints both install routes:

- `/plugin install <name>@<marketplace>` — one line, no new tooling, for anyone on
  Claude Code who just wants the skills on their machine.
- `manage-skills sources add github:owner/repo` — for anyone who wants them committed
  into their projects (teammates get them on clone), picked per project, or is not on
  Claude Code.

Both read the same files from the same repo. An existing manifest is never overwritten
without `--force`.

## Config

`~/.manage-skills/sources` — one source directory per line, in priority order (first
match wins). A trailing `# label` describes the source and shows up in `locations`:

```
~/dev/shared-skills          # Cross-language: K8s, CI, GPU, tools
~/dev/perl/shared-skills     # Shared Perl ecosystem
github:Getty/perl-skills     # Remote — fetched with `manage-skills update`
```

`~/.manage-skills/targets` — format `name:path:file`:

```
claude:.claude/skills:SKILL.md
```

`~/.manage-skills/notes.md` — optional free-form Markdown, appended to `locations`.

## Workflow

```bash
# Set up sources once, with a label saying what each one holds
manage-skills sources add ~/dev/shared-skills Cross-language: K8s, CI, tools
manage-skills sources add ~/dev/perl/shared-skills Shared Perl ecosystem

# In any project: see what exists, then link what you need
cd ~/dev/my-project
manage-skills locations
manage-skills link perl-moo dbio-core container-kubernetes

# After git clone: re-establish hardlinks
manage-skills sync

# Verify everything is linked correctly
manage-skills check
```

## Key Concepts

- Each skill has ONE source of truth (order in sources file = priority)
- Hardlinks stay in sync on your machine (same inode)
- Git sees a normal file — teammates get an independent copy on clone
- `manage-skills sync` re-establishes hardlinks after clone
- `--target` flag for non-Claude targets (extensible)

## Editing hardlinked skills — DO NOT BREAK THE INODE

A hardlinked SKILL.md shares one inode across all linked projects. Tools that **rename-and-replace** on save break the link: the path now points to a fresh inode, the other copies still point to the old one with stale content.

- **Write tool (Claude Code)**: rewrites the file → NEW INODE. Breaks hardlinks.
- **Most editors with "atomic save"**: write to temp, rename over → NEW INODE. Breaks hardlinks.
- **`cp newfile oldfile`**: copies content into existing inode → safe.
- **`cat newcontent > oldfile`** / shell redirect: truncates + writes in place → safe (same inode).
- **`sed -i`**: depends on `--follow-symlinks`/`-c` flags; default GNU sed renames → breaks. Avoid on hardlinked files.
- **`Edit` tool (Claude Code)**: empirically also breaks the inode (rewrite-and-replace). Treat as unsafe for hardlinked files.

### Rules of thumb when editing skills via AI

1. **Always use shell redirect** for hardlinked files: `cat > /path/to/SKILL.md <<'EOF' ... EOF`. Truncates + writes in place → keeps inode.
2. Avoid `Write` AND `Edit` tools on hardlinked files — both rewrite-and-replace.
3. Verify after every change: `stat -c '%i %h' path` — both inode and linkcount must match pre-edit values.
4. If linkcount dropped to 1, the link is broken — repair before continuing (see below).

### Repairing a broken hardlink chain

If you broke the link (`stat` shows linkcount=1 where it was higher):

```bash
# Find all paths sharing the OLD inode (the stale ones):
find ~/dev -inum <OLD_INODE> 2>/dev/null

# Pick one of the stale paths, overwrite it with new content (keeps OLD inode):
cat NEW_PATH > OLD_PATH

# Now relink the new path back to the old inode:
rm NEW_PATH
ln OLD_PATH NEW_PATH

# Verify all paths now share one inode with full linkcount:
stat -c '%i %h %n' <all paths>
```

### Split inodes elsewhere — the standing rule

The repair above fixes one break you caused. The same state arises silently: a copy that
was never linked, or one written by a rename-and-replace tool months ago. Two paths hold
the same bytes and nobody notices until one side is edited and the other keeps the stale
content.

**When you find files that belong to one shared chain and are byte-identical but sit on
different inodes, link them. No need to ask** — identical content means the link cannot
lose anything.

```bash
rm STRAY_PATH && ln CANONICAL_PATH STRAY_PATH
```

Differing content is a different problem: that is drift, and linking would destroy one
side. Finding split inodes across a whole machine, and deciding what to do when the
content differs, is skill `manage-skills-drift-triage`.
