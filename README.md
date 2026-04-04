# manage-skills

Hardlink-based skill sharing across AI coding tool projects.

You write a skill once. Every project that needs it gets a hardlink. Edit in one place, all projects stay in sync. Git sees a normal file, so your team gets the skill when they clone.

## The Problem

AI coding tools like Claude Code use skill files (`.claude/skills/SKILL.md`) to give the model domain knowledge. As your skill library grows, you end up with the same files copied across dozens of projects. They drift apart. Updates don't propagate. You forget which version is current.

## The Solution

**manage-skills** introduces a simple convention:

1. Each skill has exactly **one source of truth** (the project that owns it, or a shared directory)
2. Other projects get **hardlinks** to that source
3. A single CLI manages the links

Hardlinks are the key insight: they're committable (Git sees a regular file), they stay in sync on your machine (same inode), and your teammates get an independent copy when they clone (no broken symlinks pointing to paths that don't exist on their machine).

## Install

**From a clone (dev mode — symlinks the script so edits are live):**

```bash
git clone https://github.com/Getty/manage-skills.git
cd manage-skills
./install.sh
```

**One-liner (downloads a copy):**

```bash
curl -fsSL https://raw.githubusercontent.com/Getty/manage-skills/main/install.sh | bash
```

## Quick Start

```bash
# 1. Initialize config
manage-skills init

# 2. Add your skill source directories
manage-skills sources add ~/dev/shared-skills
manage-skills sources add ~/dev/perl/shared-skills
manage-skills sources add ~/dev/myframework/.claude/skills

# 3. Go to a project and see what's available
cd ~/dev/my-project
manage-skills list

# 4. Link skills you need
manage-skills link perl-moo dbio-core container-kubernetes

# 5. Or use interactive mode
manage-skills
```

## How It Works

### Source Directories

A source directory contains skill subdirectories, each with a `SKILL.md`:

```
~/dev/shared-skills/
  container-kubernetes/
    SKILL.md
  github-cli/
    SKILL.md
  kubernetes-concepts/
    SKILL.md
```

Sources are registered in `~/.manage-skills/sources` (one path per line). Order matters: when a skill name appears in multiple sources, the first one wins.

### Hardlinking

When you run `manage-skills link perl-moo`, it:

1. Finds `perl-moo/SKILL.md` in your configured sources
2. Creates `.claude/skills/perl-moo/` in the current project
3. Creates a hardlink: `ln source/perl-moo/SKILL.md .claude/skills/perl-moo/SKILL.md`

The result:
- **On your machine**: editing either copy changes both (same inode)
- **In Git**: it's a normal file, committed like any other
- **For teammates**: they get an independent copy when they clone

### Targets

By default, manage-skills targets Claude Code (`.claude/skills/SKILL.md`). The target system is extensible for other AI tools:

```bash
# Default target
manage-skills targets list
# claude  →  .claude/skills/SKILL.md

# Add another target (future use)
manage-skills targets add cursor .cursor/rules RULE.md
```

## Commands

| Command | Description |
|---|---|
| `manage-skills` | Interactive mode (fzf if available, otherwise numbered menu) |
| `manage-skills list` | Show all skills with status |
| `manage-skills link <skill>...` | Hardlink skills into current project |
| `manage-skills unlink <skill>...` | Remove skills from current project |
| `manage-skills sync` | Re-hardlink any skills that became copies |
| `manage-skills check` | Verify hardlink integrity |
| `manage-skills sources` | List configured source directories |
| `manage-skills sources add <dir>` | Add a source directory |
| `manage-skills sources remove <dir>` | Remove a source directory |
| `manage-skills targets` | List configured targets |
| `manage-skills init` | Create `~/.manage-skills/` config |

### Status Icons

| Icon | Meaning |
|---|---|
| `[*]` | Hardlinked from source (in sync) |
| `[~]` | Local copy exists but is not a hardlink (drifted) |
| `[ ]` | Available in sources but not in this project |
| `●` | Original — this project is the source of truth |

## Organizing Your Skills

A skill naming convention helps AI models find the right skill:

| Pattern | Example | Why |
|---|---|---|
| `{lang}-{name}` | `perl-moo`, `python-django` | Language prefix for language-specific skills |
| `{lang}-ai-{name}` | `perl-ai-langertha` | AI/LLM frameworks don't get lost |
| `{tool}-cli` | `vast-ai-cli` | Distinguishes CLI from API skill |
| Full words | `kubernetes` not `k8s` | Better token matching for the model |
| `{project}-{topic}` | `hi-core`, `hi-database` | Project-specific skills |

### Example Layout

```
~/dev/shared-skills/              # Cross-language (K8s, CI, tools)
  container-kubernetes/
  github-cli/
  cilium/

~/dev/perl/shared-skills/         # Shared Perl ecosystem
  perl-moo/
  perl-mcp/
  perl-dzil-distini/

~/dev/perl/my-orm/.claude/skills/ # Project owns its skills
  my-orm-core/                    # Original — source of truth
  perl-moo/                       # Hardlink from shared-skills

~/dev/hugo/shared-skills/         # Hugo ecosystem
  hugo-static-site-generator/
  hugo-ci-sites/
```

## Config Files

All config lives in `~/.manage-skills/`:

**`sources`** — One source directory per line. `~` is expanded. Comments with `#`.

```
# Cross-language
~/dev/shared-skills

# Perl ecosystem
~/dev/perl/shared-skills
~/dev/perl/dbio-dev/.claude/skills
```

**`targets`** — Format: `name:path:file`

```
claude:.claude/skills:SKILL.md
```

## FAQ

**Why hardlinks instead of symlinks?**
Symlinks contain an absolute path. When someone clones your repo, the symlink points to `/home/yourname/dev/...` which doesn't exist on their machine. Hardlinks are just regular files from Git's perspective — everyone gets an independent copy.

**What happens when I `git clone` a project with hardlinked skills?**
You get normal independent files. Run `manage-skills sync` to re-establish hardlinks to your local sources (if you have them).

**What if I don't have the source directories?**
The skills still work — they're regular committed files. You just can't sync updates until you set up the sources.

**Does this work across filesystems?**
No, hardlinks require the same filesystem. Your source directories and projects must be on the same mount.

**Can I use this with tools other than Claude Code?**
Yes. Add a target: `manage-skills targets add cursor .cursor/rules RULE.md`. The skill file format may differ, but the hardlink mechanics are the same.

## Requirements

- Bash 4+ (for associative arrays)
- Standard Unix tools: `stat`, `ln`, `find`, `grep`
- Optional: `fzf` for interactive mode

## License

MIT
