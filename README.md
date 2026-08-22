<p align="center">
  <a href="https://github.com/Getty/manage-skills">
    <img src="assets/github.png" width="800"
         alt="manage-skills — a llama in dungarees at a telephone switchboard, patching yellow cords into a wall of numbered pigeonhole cabinets">
  </a>
</p>

# manage-skills

**Hardlink-based skill sharing across AI coding tool projects.**

Write a skill once. Every project that needs it gets a hardlink. Edit in one place and
all of them change. Git sees a normal file, so your team gets the skill when they clone.

```
~/dev/shared-skills  — Cross-language: K8s, CI, tools
  [ ] ansible-basics        [~] github-cli            [ ] prometheus-metrics
  [*] cilium                [ ] gpu-nvidia            [*] rke2
  [ ] container-kubernetes  [ ] grafana-dashboards    [ ] terraform-core

~/dev/perl/shared-skills  — Shared Perl ecosystem
  [ ] perl-ai-langertha     [ ] perl-mcp              [*] perl-moo

This project (source of truth)
   ● my-orm-core

Legend: [*] hardlinked  [~] local copy  [ ] available  ● original
```

## The Problem

AI coding tools use skill files (`.claude/skills/SKILL.md`) to give the model domain
knowledge. As your library grows you end up with the same file copied across dozens of
projects. They drift apart, updates don't propagate, and nobody knows which copy is
current.

## The Solution

1. Each skill has exactly **one source of truth** — the project that owns it, or a
   shared directory.
2. Every other project gets a **hardlink** to that source.
3. One CLI manages the links.

Hardlinks are the trick. They're committable (Git sees a regular file), they stay in
sync on your machine (same inode), and teammates get an independent copy on clone — no
broken symlink pointing at `/home/yourname/dev/…`.

## Install

**As a Claude Code plugin** — puts `manage-skills` on the Bash tool's `PATH` and brings
its skills along, so Claude knows how to use it:

```
/plugin marketplace add Getty/marketplace
/plugin install manage-skills@getty
```

**As a Codex plugin** — same repo, same skills:

```
codex plugin marketplace add Getty/marketplace
codex plugin add manage-skills@getty
```

A Codex plugin manifest cannot put anything on `PATH`, so there the agent calls the
script by path — it ships in the plugin root, three levels above the skill that
documents it, and the skill says so. Everything else behaves identically. If you want
the command in your own shell as well, install it properly with one of the routes below;
that is worth doing in either harness, since a plugin only ever reaches the agent's
shell, never yours.

**One-liner** (downloads a standalone copy):

```bash
curl -fsSL https://raw.githubusercontent.com/Getty/manage-skills/main/install.sh | bash
```

**From a clone** (dev mode — symlinks the script so your edits are live):

```bash
git clone https://github.com/Getty/manage-skills.git
cd manage-skills
./install.sh
```

**Homebrew:**

```bash
brew install Getty/manage-skills/manage-skills
```

## Quick Start

```bash
manage-skills init                    # create ~/.manage-skills/

# Register where your skills live. The trailing label is optional and shows up
# in `locations`.
manage-skills sources add ~/dev/shared-skills      Cross-language: K8s, CI, tools
manage-skills sources add ~/dev/perl/shared-skills Shared Perl ecosystem
manage-skills self install                         # the skills this tool ships

# Somebody else's set: a GitHub owner name is all it takes.
manage-skills sources add Getty                    # github.com/Getty/skills

cd ~/dev/my-project
manage-skills locations               # where does everything come from?
manage-skills link perl-moo dbio-core # link what you need
manage-skills                         # …or pick interactively
```

## Commands

| Command | Description |
|---|---|
| `manage-skills` | Interactive mode — fzf if available, otherwise a numbered menu |
| `manage-skills list` | All skills with their link status, grouped by source |
| `manage-skills locations` | Where skills come from, per source |
| `manage-skills link <skill>…` | Hardlink skills into the current project |
| `manage-skills unlink <skill>…` | Remove skills from the current project |
| `manage-skills sync` | Re-hardlink any skill that became a plain copy |
| `manage-skills update [name…]` | Pull remote sources; `--check` only reports |
| `manage-skills package [dir]` | Make a skill directory installable by others |
| `manage-skills check` | Verify hardlink integrity |
| `manage-skills sources` | List source directories |
| `manage-skills sources add <dir\|repo\|owner> [label]` | Add a source — a directory, a git repo, or a GitHub owner (their `skills` repo) |
| `manage-skills sources remove <dir>` | Remove a source |
| `manage-skills targets` | List configured targets |
| `manage-skills self` | Where this install and its own skills live |
| `manage-skills self install` | Register the shipped skills as a source |
| `manage-skills self update` | Update the script and the shipped skills |
| `manage-skills init` | Create `~/.manage-skills/` |

Every command takes `--target <name>` (default: `claude`).

### Status Icons

| Icon | Meaning |
|---|---|
| `[*]` | Hardlinked from source — in sync |
| `[~]` | A local copy exists but is not a hardlink — drifted |
| `[ ]` | Available in a source, not in this project |
| `●` | Original — this project is the source of truth |

## How It Works

### Source directories

A source directory holds skill subdirectories, each with a `SKILL.md`:

```
~/dev/shared-skills/
  container-kubernetes/SKILL.md
  github-cli/SKILL.md
  cilium/SKILL.md
```

Sources are listed in `~/.manage-skills/sources`, **in priority order** — when a skill
name appears in two sources, the first one wins.

### Hardlinking

`manage-skills link perl-moo` finds `perl-moo/SKILL.md` in your sources, creates
`.claude/skills/perl-moo/` in the current project, and hardlinks the file into it —
along with every other file in the skill's directory, `references/` and `templates/`
included, so a relative link inside a SKILL.md still resolves in the project that
received it.

- **On your machine**: editing either path changes both — same inode
- **In Git**: a normal file, committed like any other
- **For teammates**: an independent copy on clone; `manage-skills sync` relinks it to
  their own sources

### Drift on purpose

`check` marks a skill `[~]` when the project holds its own copy instead of a hardlink,
and offers `sync` to relink it. That reads like an error report, and often it is one —
an `Edit` tool rewrote the file and quietly detached it.

But the same state is also a perfectly good way to propose a change. A project adapts a
shared skill because that project needs something different; the copy diverges, and the
divergence shows up as **a normal commit in that repo** — reviewable in a pull request,
visible in `git log`, attributable to whoever made it. Nothing is lost and nothing is
forced on anyone else. Whoever maintains the source of truth then decides whether it
belongs upstream: take it, and every project on that hardlink has it; leave it, and the
one project keeps its local variant.

That is the whole workflow:

```bash
# in the project — an ordinary edit, an ordinary commit
$EDITOR .claude/skills/perl-moo/SKILL.md
git commit -am "perl-moo: our projects need the strict variant"

manage-skills check          # [~] perl-moo (copy, expected hardlink from …)
```

`sync` protects that on its own. It compares content before relinking:

```
$ manage-skills sync
  relinked perl-mcp
  diverged perl-moo  (local content differs — kept)

  4 ok, 1 relinked, 1 diverged
  Diverged copies were kept. Decide whether the change belongs upstream,
  then rerun with --force to relink them.
```

A copy that still reads exactly like its source is relinked without asking — that is the
common case, where an `Edit` detached the inode without changing a word, and nothing can
be lost. A copy that reads *differently* is somebody's work, so it stays and gets named.
`sync --force` is the deliberate override, for once the change has been taken upstream or
discarded.

And because the divergence is committed, even a forced sync only removes it from the
working tree, never from the history.

The `manage-skills-drift-triage` skill covers the other direction — telling a deliberate
divergence apart from a link that broke by accident, across a whole machine.

### Remote sources

A source doesn't have to be a directory on your machine. Point it at a repository and
manage-skills keeps a copy for you:

```bash
manage-skills sources add github:someone/their-skills Their skills
manage-skills link perl-moo perl-mcp

manage-skills update --check   # anything new upstream?
manage-skills update           # fetch it
```

**An owner name on its own is enough**, if their repository is called `skills` —
which is the convention this tool sets, and what `package` tells people to use:

```bash
manage-skills sources add Getty        # → github.com/Getty/skills
manage-skills link getty-perl-moo getty-git-usage
```

Exactly one name is tried, never a chain of guesses. An owner with no `skills` repo
gets told what to type instead, rather than being quietly resolved somewhere else:

```
$ manage-skills sources add nobodyhere
  nobodyhere → github:nobodyhere/skills
error: github.com/nobodyhere/skills not found.
  Give the repo in full:
    manage-skills sources add github:nobodyhere/<repo>
```

A directory of that name in the way always wins — what is on disk is never guessed
past — and the shorthand is printed in case that wasn't what you meant.

No Claude Code required — this is bash and git. Skills from a remote source hardlink into
your projects exactly like local ones, get committed with the repo, and reach teammates
on clone.

**Updates land everywhere at once.** `update` writes changed files *in place*, so the
inode survives and every project already linked to that skill has the new content the
moment `update` finishes. There is nothing to run in each project afterwards:

```
$ manage-skills update
github:Getty/skills
  2 updated, 1 new
```

A skill that disappears upstream is reported, never deleted — a project may still be
linked to it. Where the repo keeps its skills (`skills/`, `.claude/skills/`, or the root)
is detected, not configured.

## Publishing Your Skills

Someone says "I want your Perl skills." They shouldn't have to adopt your tooling to get
them. `manage-skills package` turns a skill directory into something installable both
ways, from the same files:

```
$ cd ~/dev/perl/shared-skills && manage-skills package
Packaging ~/dev/perl/shared-skills
  12 skills in ./skills: perl-moo perl-mcp perl-release-dist-ini …

Wrote ~/dev/perl/shared-skills/.claude-plugin/plugin.json
  Fill in the description before publishing.

Add to your marketplace's .claude-plugin/marketplace.json:

    {
      "name": "perl-skills",
      "source": { "source": "github", "repo": "you/perl-skills" },
      "description": "..."
    }

Then people can take your skills three ways:
  Claude Code   /plugin install perl-skills@<marketplace>
  Codex         codex plugin add perl-skills@<marketplace>
  Any tool      manage-skills sources add github:you/perl-skills
```

**Call the repo `skills` and that last line gets shorter still** — `package` prints
`manage-skills sources add you`, because an owner name alone resolves to their `skills`
repo. It costs nothing to follow and saves everyone who takes your set from having to
remember what you called it.

The three routes suit different people, which is why it sets up all of them:

- **`/plugin install`** and **`codex plugin add`** — one line, no new tooling, for
  anyone who just wants your skills on their machine.
- **`manage-skills sources add`** — for anyone who wants the skills *committed into
  their projects* so teammates get them on clone, wants to pick per project, or uses
  neither of those two CLIs.

Nothing is duplicated. Claude Code and Codex both read `<name>/SKILL.md`, so one skills
directory serves both — only the two manifests differ, and both point at the directories
where they already are. An existing manifest is never overwritten without `--force`.

### Grouping a large set

Once a set outgrows a handful of skills, the natural move is one repo with groups:

```
Getty/skills/
  perl/
    perl-core/SKILL.md
    perl-moose/SKILL.md
  k8s/
    k8s-basics/SKILL.md
```

manage-skills finds these. It looks for skill directories in `skills/`, `.claude/skills/`
or the repo root, and when a candidate holds none directly, it looks one level deeper.
Not deeper than that: a `SKILL.md` further down is far more likely an example or a test
fixture than a skill anyone meant to publish.

The groups are organisation in *your* repo and nothing more. A project links skills by
name and `sources.d/<name>/` is flat, so `perl/perl-core` arrives simply as `perl-core`.
That also means two groups cannot offer the same name: `perl/core` and `bash/core` would
collide the moment they are flattened, so it is reported rather than silently resolved.

`package` follows the same shape. A set that lives in one directory gets
`"skills": "./skills"`; a grouped set gets the array form, which both Claude Code and
Codex accept:

```json
"skills": ["./perl/perl-core", "./perl/perl-moose", "./k8s/k8s-basics"]
```

### Why the three routes are not interchangeable

A plugin installs **everything it ships**. A hardlink installs **what you asked for**.
That difference matters more than it first looks, because a skill's description is not
neutral information — it is an offer. Every skill visible to an agent is a suggestion it
can act on, and eventually it will: a `perl-moose` skill sitting in the list of a project
that uses Moo gets picked up sooner or later, and nothing in the result says why.

Progressive disclosure keeps the skill's *body* out of the context until it is used, so a
large set costs almost nothing in tokens. It does not keep the *description* out — and
the description is the part that steers behaviour.

So for a small, coherent set, where "all or nothing" is also true in substance, a plugin
is the better route. For a large or mixed one, distributing it as a source and linking
per project is not merely tidier: it is the only way an agent never sees the skills that
have no business in this project.

**The routes are not a choice you make once, and not one you make for your users.** The
same repository serves all three at the same time: `package` writes both plugin
manifests, and the skills directory it points at is the very one `sources add` reads. So
somebody can install your set as a Claude Code plugin and update it with
`/plugin update`, somebody else can take it through Codex with `codex plugin add`, and a
third can hardlink individual skills into their projects — from one set of files, at the
same version, with no coordination between them.

manage-skills itself is distributed exactly that way, and that is the point: the
conventional plugin route is fully supported rather than merely tolerated. If plugin
updates are all you want, take them; hardlinks are there for when you need to pick per
project, want the skills committed into a repo, or run neither CLI.

Neither harness fully fixes this after the fact. Claude Code's per-skill visibility
setting explicitly excludes plugin skills — *"Plugin skills are not affected by
`skillOverrides`. Manage those through `/plugin` instead."* Codex can disable individual
skills with `[[skills.config]] enabled = false`, including plugin ones, but that is
opt-out: the default is visible.

What you *can* ship yourself, in both worlds, is a skill that never volunteers:

```yaml
# Claude Code — in the SKILL.md frontmatter
disable-model-invocation: true
```

```yaml
# Codex — in agents/openai.yaml beside the skill
policy:
  allow_implicit_invocation: false
```

Both keep `/name` and `$name` working while stopping the agent from reaching for the
skill on its own.

Reach for that sparingly, though, because there is a division of labour it can wreck. An
agent that *delegates* needs the map: names and descriptions of everything available, so
it knows what exists and which subagent to hand a task to. Hiding skills from it defeats
the very arrangement it relies on.

The split that works looks like this:

- **The main agent gets the listing** — names and descriptions, the map. It decides and
  delegates.
- **Subagents get the content**, preloaded rather than offered. That is what
  [`briefing`](https://github.com/Getty/briefing) does: the agent wakes up already
  holding the skills it was declared to need, instead of having to find them.
- **The real boundary is what you linked into the project.** A skill that isn't there
  cannot be offered to anyone, and no flag is needed to keep it quiet.

So `disable-model-invocation` earns its place where a skill would actively mislead if the
main agent reached for it — `perl-moose` in a house that also has Moo projects — and not
as a general precaution.

### Where skills live

`manage-skills locations` answers "where does this come from?" from config and disk, so
there is no inventory to keep up to date:

```
~/dev/shared-skills  — Cross-language: K8s, CI, tools
  cilium                container-kubernetes  github-cli
  gpu-nvidia            rke2                  vast-ai

~/dev/perl/shared-skills  — Shared Perl ecosystem
  cilium*                perl-mcp              perl-moo

Owned by my-orm (source of truth — no source provides these)
  my-orm-core           my-orm-migrations

* shadowed — an earlier source already provides that name, so this
  copy never wins a link or a sync.
```

That `*` is the one worth watching. A second source offering a name an earlier source
already provides is never linked and never synced — the usual reason a project's copy
quietly stops updating.

Whatever can't be derived — naming conventions, which skills pair up, which ones are
conditional — goes in `~/.manage-skills/notes.md`, which `locations` prints at the end.

### Column layout

On a terminal, `list` and `locations` size their columns to your terminal width. Piped
or redirected output falls back to one skill per line, so `manage-skills list | grep …`
keeps working.

### Targets

Two targets are configured out of the box, because the two big agent CLIs look in
different places:

```bash
manage-skills targets list
# claude  →  .claude/skills/SKILL.md
# codex   →  .agents/skills/SKILL.md

manage-skills link perl-moo                  # into .claude/skills/
manage-skills link perl-moo --target codex   # into .agents/skills/
```

Codex discovers skills in `.agents/skills/` — at the repo root, in the current directory,
and in `$HOME/.agents/skills`. Same hardlink mechanics, different directory, so a skill
can serve both from one source of truth.

Adding another tool is one line:

```bash
manage-skills targets add cursor .cursor/rules RULE.md
manage-skills list --target cursor
```

*(Upgrading from an older install? The `codex` target only lands in fresh configs — add
it with `manage-skills targets add codex .agents/skills SKILL.md`.)*

## Naming Skills

A convention helps the model pick the right skill:

| Pattern | Example | Why |
|---|---|---|
| `{lang}-{name}` | `perl-moo`, `python-django` | Language prefix keeps ecosystems apart |
| `{lang}-ai-{name}` | `perl-ai-langertha` | AI/LLM frameworks don't get lost |
| `{tool}-cli` | `vast-ai-cli` | Distinguishes the CLI skill from the API one |
| Full words | `kubernetes`, not `k8s` | Better token matching for the model |
| `{project}-{topic}` | `my-orm-core` | Project-owned skills read as their own thing |

Record your own conventions in `~/.manage-skills/notes.md` so `locations` shows them.

## Config Files

Everything lives in `~/.manage-skills/` (override with `MANAGE_SKILLS_HOME`).

**`sources`** — one directory per line, in priority order. `~` is expanded. A full-line
`#` is a comment; a trailing `#` is that source's label.

```
~/dev/shared-skills                  # Cross-language: K8s, CI, tools
~/dev/perl/shared-skills             # Perl ecosystem
~/dev/perl/dbio-dev/.claude/skills   # DBIO ORM, per-repo sources
```

**`targets`** — `name:path:file`.

```
claude:.claude/skills:SKILL.md
```

**`notes.md`** — optional free-form Markdown, printed at the end of `locations`.

Remote sources add two directories: `cache/<name>/` is the git checkout, `sources.d/<name>/`
holds the files your projects hardlink against. Keeping them apart is what lets an update
reach every project at once — see the FAQ below.

## FAQ

**Why hardlinks instead of symlinks?**
A symlink stores a path. Clone the repo on another machine and it points at
`/home/yourname/dev/…`, which isn't there. A hardlink is just a regular file to Git —
everyone gets a working independent copy.

**What happens when I `git clone` a project with hardlinked skills?**
You get normal files. `manage-skills sync` re-establishes hardlinks against your own
sources, if you have them.

**What if I don't have the source directories at all?**
The skills still work — they're committed files. You just can't sync updates until you
set up sources.

**Does this work across filesystems?**
No. Hardlinks need one filesystem, so sources and projects must be on the same mount.

**A skill I added never shows up as linked. Why?**
Check `manage-skills locations` for a `*` next to its name — an earlier source is
shadowing it. Reorder `~/.manage-skills/sources`.

**Why does a remote source get stored twice?**
`git pull` writes changed files by rename-and-replace, which mints a new inode and leaves
every hardlink pointing at the old content — the exact drift this tool exists to prevent.
So the checkout stays separate, and `update` copies changed files into the linked copy
with `cat >`, which writes in place. The inode survives, and every project linked to that
skill is up to date the instant `update` returns.

**Can I use this with tools other than Claude Code?**
Yes. `manage-skills targets add cursor .cursor/rules RULE.md`. The file format differs
per tool, the hardlink mechanics don't.

**How do I edit a skill without breaking every other copy?**
Use `cat > file` or `cp new old`. Anything that saves by rename-and-replace — including
most editors' "atomic save" — mints a new inode and silently strands every other
project on the old content. The shipped `manage-skills` skill has the full rules.

## Requirements

- Bash 3.2+ — runs on the system bash macOS ships
- Standard Unix tools: `stat`, `ln`, `find`, `grep`
- `git` — only for remote sources
- Optional: `fzf` for interactive mode, `tput` for column width detection

## License

MIT
