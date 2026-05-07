---
name: manage-skills
description: "manage-skills CLI — hardlink-based skill sharing across AI coding tool projects. Use when adding, removing, syncing, or checking shared skills."
user-invocable: true
---

# manage-skills — Hardlink-Based Skill Sharing

CLI tool for managing shared skill files across projects via hardlinks. Config lives in `~/.manage-skills/`.

## Commands

```bash
manage-skills                        # Interactive mode (fzf or numbered menu)
manage-skills list                   # Show all skills with status
manage-skills link <skill>...        # Hardlink skills into current project
manage-skills unlink <skill>...      # Remove skills from current project
manage-skills sync                   # Re-hardlink stale copies
manage-skills check                  # Verify hardlink integrity
manage-skills sources                # List source directories
manage-skills sources add <dir>      # Add a skill source
manage-skills sources remove <dir>   # Remove a skill source
manage-skills targets                # List configured targets
manage-skills targets add <n> <p> <f> # Add target (name:path:file)
manage-skills init                   # Create ~/.manage-skills/ config
```

## Status Icons

- `[*]` — hardlinked from source (in sync)
- `[~]` — local copy, not a hardlink (drifted)
- `[ ]` — available but not linked
- `●` — original, this project is the source of truth

## Config

`~/.manage-skills/sources` — one source directory per line:

```
~/dev/shared-skills
~/dev/perl/shared-skills
~/dev/perl/dbio-dev/.claude/skills
```

`~/.manage-skills/targets` — format `name:path:file`:

```
claude:.claude/skills:SKILL.md
```

## Workflow

```bash
# Set up sources once
manage-skills sources add ~/dev/shared-skills
manage-skills sources add ~/dev/perl/shared-skills

# In any project: link what you need
cd ~/dev/my-project
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
