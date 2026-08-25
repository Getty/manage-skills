---
name: manage-skills
description: Use when adding, removing, syncing or checking shared skills, when asking where a skill comes from, or before editing any file inside a hardlinked skill directory.
user-invocable: true
---

# manage-skills — Hardlink-Based Skill Sharing

CLI tool for sharing whole skill directories across projects via hardlinks. Config lives in `~/.manage-skills/`.

> **⚠️ Editing any file in a linked skill? Use `cat > file` — NOT the `Edit`/`Write` tools.**
> They rewrite-and-replace → new inode → silently breaks the hardlink to every other
> project. Full rules + repair in
> [Editing hardlinked skills](#editing-hardlinked-skills--do-not-break-the-inode) below.

## What gets linked: the directory

A skill is a **directory**, and the whole directory is what gets hardlinked — `SKILL.md`,
`references/`, `templates/`, `scripts/`, every regular file in it. Each one shares an
inode with its counterpart in the source, subdirectories included.

`SKILL.md` is not the linked thing. It is the file that *identifies* a directory as a
skill, which is why discovery keys on it and why a target definition names it
(`claude:.claude/skills:SKILL.md`). It gets linked exactly like every other file in the
directory, with no special status once linking starts.

This matters for the rule below: it applies to **every file in the skill**, not just the
entry file. A `references/api.md` detaches from its source exactly the way a `SKILL.md`
does, and just as silently.

A project linked by an older version holds only its `SKILL.md`. `manage-skills sync`
upgrades it in place — the rest of the directory is hardlinked in, subdirectories and
all. No unlink, no flag.

## Commands

```bash
manage-skills                        # Interactive mode (fzf or numbered menu)
manage-skills list                   # Show all skills with status
manage-skills locations              # Where skills come from, per source
manage-skills link <skill>...        # Hardlink skills into current project
manage-skills unlink <skill>...      # Remove skills from current project
manage-skills unlink <skill> --force # …even if it holds files no source has
manage-skills sync                   # Re-hardlink stale copies (keeps diverged ones)
manage-skills sync --force           # …and relink the diverged ones too
manage-skills update [name...]       # Pull remote sources (--check only reports)
manage-skills package [dir]          # Make a skill directory installable by others
manage-skills check                  # Verify hardlink integrity
manage-skills sources                # List source directories
manage-skills sources add <dir|repo|owner> [label]  # Add a source: directory,
                                     #   repo, or GitHub owner (their skills repo)
manage-skills sources remove <dir>   # Remove a skill source
manage-skills targets                # List configured targets
manage-skills targets add <n> <p> <f> # Add target (name:path:file)
manage-skills self                   # Where this install and its own skills live
manage-skills self install           # Register the shipped skills as a source
manage-skills self update            # Update the script and the shipped skills
manage-skills init                   # Create ~/.manage-skills/ config
```

Every command takes `--target <name>` (default: `claude`).

## If the `manage-skills` command is not found

Installed as a Claude Code plugin, the command is already on the Bash tool's `PATH`.
Under Codex there is no such mechanism — a plugin manifest there cannot put anything on
`PATH` — so the script has to be called by path instead. It sits in the root of this
plugin, three levels above this file:

```bash
../../../manage-skills list          # relative to this SKILL.md
```

Resolve that against the absolute path of this file, which the skill listing gives you.
Everything else in this document works the same; only the invocation differs.

If you want the command available in your own shell too — in either harness — install it
once and the path juggling stops:

```bash
curl -fsSL https://raw.githubusercontent.com/Getty/manage-skills/main/install.sh | sh
```

## Status Icons

- `[*]` — hardlinked from source (in sync)
- `[~]` — local copy, not a hardlink (drifted), or holding files no source has
- `[ ]` — available but not linked
- `●` — original, this project is the source of truth

`check` and `sync` name any file in a project's skill directory that no source has a
copy of — one somebody added here, or one a source dropped while this project kept it.
Nothing can relink those, so they are reported and left alone; fold one into the source
if it belongs to the skill, or move it out if it does not. `unlink` refuses to `rm -rf`
over them unless `--force` says so.

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
/plugin marketplace add Getty/marketplace
/plugin install manage-skills@getty
```

Both routes can be active at once, and then they age apart: the plugin cache holds the
version you installed, the checkout holds whatever you last pulled, and both sit on
`PATH`. Whichever comes first answers — and a copy that predates a feature reports the
absence of that feature as "nothing to do", which is how a `sync` comes back clean while
no skill directory is linked past its `SKILL.md`. `manage-skills self` names every other
`manage-skills` on `PATH` with its version. **Read that before believing a quiet result.**

## Remote sources

A source can be a repository instead of a directory:

```bash
manage-skills sources add github:someone/their-skills Their skills
manage-skills update --check   # anything new upstream?
manage-skills update           # fetch it
```

**A bare owner name resolves to that owner's `skills` repo** — `manage-skills sources
add Getty` is `github:Getty/skills`. That is the convention this tool sets, so it is
the line to suggest when someone asks how to get a published set. Exactly one name is
tried: an owner with no `skills` repo is told to give the repo in full, never resolved
somewhere else. A directory of that name in the current directory wins over the owner.

The local checkout of a `skills` repo is named after its owner (`sources.d/getty-skills`),
because every owner has one and `sources.d/` is flat.

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

- `/plugin install <name>@<marketplace>` (Claude Code) or
  `codex plugin add <name>@<marketplace>` (Codex) — one line, no new tooling, for
  anyone who just wants the skills on their machine.
- `manage-skills sources add github:owner/repo` — for anyone who wants them committed
  into their projects (teammates get them on clone), picked per project, or uses neither
  of those CLIs. A repo called `skills` shortens that to `manage-skills sources add
  <owner>`, and `package` prints whichever form actually works for the repo.

Both plugin systems read `<name>/SKILL.md`, so one skills directory serves both — only
the manifests differ (`.claude-plugin/` and `.codex-plugin/`). An existing manifest is
never overwritten without `--force`.

## Config

`~/.manage-skills/sources` — one source directory per line, in priority order (first
match wins). A trailing `# label` describes the source and shows up in `locations`:

```
~/dev/shared-skills          # Cross-language: K8s, CI, GPU, tools
~/dev/perl/shared-skills     # Shared Perl ecosystem
github:Getty/perl-skills     # Remote — fetched with `manage-skills update`
```

`~/.manage-skills/targets` — format `name:path:file`. Two are configured by default,
because Claude Code and Codex look in different places:

```
claude:.claude/skills:SKILL.md
codex:.agents/skills:SKILL.md
```

`manage-skills link <skill> --target codex` puts the same source of truth into
`.agents/skills/`, which is where Codex discovers skills. Older configs predate the
codex entry: `manage-skills targets add codex .agents/skills SKILL.md`.

`~/.manage-skills/notes.md` — optional free-form Markdown, appended to `locations`.

## Workflow

```bash
# Set up sources once, with a label saying what each one holds
manage-skills sources add ~/dev/shared-skills Cross-language: K8s, CI, tools
manage-skills sources add ~/dev/perl/shared-skills Shared Perl ecosystem

# In any project: see what exists, then link what you need
cd ~/dev/my-project
manage-skills locations
manage-skills link getty-perl-moo dbio-core container-kubernetes

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

Every file in a linked skill directory shares one inode with its counterpart in the source, and with every other project that links the skill. Tools that **rename-and-replace** on save break that: the path now points to a fresh inode, and every other copy still points to the old one with stale content.

`SKILL.md` is not a special case here — `references/`, `templates/` and `scripts/` are hardlinked the same way and detach the same way, without anything appearing to go wrong.

- **Write tool (Claude Code)**: rewrites the file → NEW INODE. Breaks hardlinks.
- **Most editors with "atomic save"**: write to temp, rename over → NEW INODE. Breaks hardlinks.
- **`cp newfile oldfile`**: copies content into existing inode → safe.
- **`cat newcontent > oldfile`** / shell redirect: truncates + writes in place → safe (same inode).
- **`sed -i`**: depends on `--follow-symlinks`/`-c` flags; default GNU sed renames → breaks. Avoid on hardlinked files.
- **`Edit` tool (Claude Code)**: empirically also breaks the inode (rewrite-and-replace). Treat as unsafe for hardlinked files.

### Rules of thumb when editing skills via AI

1. **Always use shell redirect** for any file in a linked skill: `cat > /path/to/references/api.md <<'EOF' ... EOF`. Truncates + writes in place → keeps inode.
2. Avoid `Write` AND `Edit` tools on hardlinked files — both rewrite-and-replace.
3. Verify after every change: `stat -c '%i %h' path` — both inode and linkcount must match pre-edit values.
4. If linkcount dropped to 1, the link is broken — repair before continuing (see below).

### Breaking it on the source side reads as someone else's edit

The rules above are usually applied to a skill *inside a project*. Doing it to the
**source** is worse, and the report it produces is misleading: the source becomes a new
inode with new content, every project still holds the old one, and `sync` sees two files
with two inodes and different content — the same shape a deliberate local edit makes. It
reports every one of those projects as `diverged` and keeps them, so a change made once
upstream now needs `sync --force` in each project instead of already being there.

Nothing on disk tells the two apart. The project's git history does: a copy that really
diverged has a commit that changed it. Editing the source in place avoids the question
entirely — that is the whole point of the rule.

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
