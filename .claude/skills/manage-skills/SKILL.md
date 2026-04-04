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
