---
name: manage-skills-drift-triage
description: "Finding and resolving hardlink drift under manage-skills — auditing a whole machine for split inodes, and telling a harmless missed link apart from real content divergence. Use when the same skill name turns up with different content across repos, before blindly running `manage-skills sync`, or when a project's skill copy never seems to update."
user-invocable: true
---

# Skill Hardlink Drift — Audit and Triage

`manage-skills` keeps skills in sync via hardlinks: one inode, many paths. Copies drift
apart anyway. This skill covers the two things the CLI does not do for you: **auditing
across repos** (`check`/`sync` only ever look at `$PWD`), and **deciding what to do**
once the content actually differs.

The rule for the easy case lives in skill `manage-skills`: byte-identical files on
different inodes get linked on sight, no permission needed. Everything below is for when
that rule does not apply.

## How drift actually happens

- **A hardlinked `SKILL.md` was edited with `Edit`/`Write`.** Both rewrite-and-replace →
  new inode for the edited path, old inode (and its stale content) stays behind on every
  other path. Linkcount on the edited file drops to 1. Skill `manage-skills` has the rule
  (`cat > file`) and the repair steps.
- **A project got a one-time copy instead of a link.** Common when a skill set was
  bootstrapped by copying files in, not by `manage-skills link`. The copy never enters
  the sync loop — it just ages while the source keeps evolving.
- **A project is shadowed by priority order.** `discover_skills` dedups by name and the
  *first* source in the file wins. If project B provides its own `foo` but project A is
  listed earlier and also provides a `foo`, B's copy never wins — and never gets
  refreshed either, because `sync` only relinks against the winning source.
  `manage-skills locations` marks these with `*`, so this one is now visible without an
  audit.
- **A directory that should be a source isn't registered at all** (`~/.claude/skills` is
  the usual one). Project-local copies of those skills have no sync path back to the
  canonical copy, so nothing ever compares them.

## Finding drift

### Same machine, one skill name across many repos

Group every `.claude/skills/*/SKILL.md` by skill *name*, then by **inode** (same inode =
already fine) and by **content hash** (same hash, different inode = link them; different
hash = real drift, go to the decision tree).

```bash
# 1. find every .claude/skills dir, skip build artifacts / plugin caches / snapshots
find ~ -maxdepth 7 \( -name node_modules -o -name .git -o -name .build -o -name .cache \
    -o -iname "Backup*" -o -path "*/.claude/plugins/*" \) -prune \
    -o -type d -path "*/.claude/skills" -print

# 2. for one skill name across N candidate dirs, compare content + link state
for f in path/to/*/SKILL.md; do stat -c '%i %h %s  %n' "$f"; done
diff -u master/SKILL.md candidate/SKILL.md
```

### Whole-tree sweep for split inodes

Set `ROOT` to the directory tree holding your projects; the scan walks it two levels deep
looking for `.claude` directories and reports files that are identical but unlinked.

```bash
ROOT=~/dev
cd "$ROOT"
perl -e '
use File::Find; use Digest::MD5;
my %g;
for my $p (glob("*"), glob("*/*")) {
  next unless -d "$p/.claude";
  find(sub { return unless -f && /\.md$/;
    my $f = $File::Find::name; (my $rel = $f) =~ s{^\Q$p\E/}{};
    open my $fh,"<",$f or return;
    push @{$g{$rel}}, [$p, (stat $f)[1], Digest::MD5->new->addfile($fh)->hexdigest];
  }, "$p/.claude");
}
for my $rel (sort keys %g) {
  my @e = @{$g{$rel}}; next if @e < 2;
  my %by; push @{$by{$_->[2]}}, $_ for @e;
  for my $md5 (keys %by) {
    my @same = @{$by{$md5}}; next if @same < 2;
    my %ino; $ino{$_->[1]}++ for @same; next if keys %ino == 1;
    printf "%-46s identical in %d, %d inodes: %s\n", $rel, scalar(@same),
      scalar(keys %ino), join(", ", map { $_->[0] } sort { $a->[0] cmp $b->[0] } @same);
  }
}' 2>/dev/null
```

Two limits on acting from this sweep:

1. **Only files that are meant to be one file** — `.claude/skills`, `.claude/agents`,
   `.claude/rules`, and whatever else a source of truth governs. Never link two files
   that merely happen to match (`LICENSE`, `.gitignore`, a boilerplate config). There a
   later single-project edit would silently change every other project too, which is the
   opposite of what anyone expects outside a shared-skill chain.
2. **Identical content only.** Differing content is drift, and linking destroys one side.
   Triage below, `cat` the canonical version over the other, *then* link. Say which side
   you overwrote and why — a stale copy that is simply behind is the common case, real
   divergence is not.

**Version note:** `manage-skills check` counts project-owned skills as `originals`.
Copies older than the fix for that aborted on the first such skill (`set -o pipefail`
plus a `grep` that matched nothing) and printed only the header. A `check` that exits 1
with no findings means a stale copy of the tool, not a broken project.

## Decision tree

**1. Same content, different inode (harmless).**
Nothing at risk — `manage-skills sync` in the consuming project fixes it. The common case
after a fresh clone or a manual `cp` instead of `ln`.

**2. Different content — diff it before touching anything.**

- **All changes point one direction** (the local copy is a strict subset of the newer
  master — nothing exists only in the local copy): pure staleness, no customization to
  lose. Relink straight to master:
  ```bash
  rm path/to/consumer/SKILL.md
  ln path/to/source/SKILL.md path/to/consumer/SKILL.md
  stat -c '%i %h' path/to/source/SKILL.md path/to/consumer/SKILL.md   # same inode, linkcount +1
  ```
- **The local copy has content that doesn't exist upstream and is useful in general**
  (not tied to one project's specifics): fold it into the master file first (via `cat >`
  on the source, never `Edit`/`Write`), then relink the consumer as above so everyone
  benefits.
- **The local copy's differences are specific to that one project** (a closed repo that
  only consumes shared skills and never contributes back, a genuinely different domain
  convention, intentionally incompatible instructions): don't silently overwrite it, and
  don't leave it collision-named with the shared skill either. Rename it to a
  project-prefixed skill (`<project>-<skill-name>`) so it reads as its own thing, and
  leave it unlinked — it now has its own life and its own inode. It will show up under
  "Owned by …" in `manage-skills locations`, so the next audit sees it for what it is.
- **A source's copy is shadowed by an earlier-priority source** (the `*` in `locations`):
  either accept that the earlier source wins and remove the redundant skill folder, or
  reorder `~/.manage-skills/sources` if the shadowed one should actually be the winner.

**3. A whole directory tree duplicates another one (not per-skill drift).**
A full second copy of a multi-repo project — own internal hardlink cluster, disconnected
from the live one — is not a sync bug to fix skill-by-skill. Confirm whether it's an
intentional backup/snapshot, note its freeze date, and keep it out of
`~/.manage-skills/sources` and out of future audits.

## Closing a systemic gap

If drift traces back to a structural hole (a directory that should be a source but isn't,
a project treated as a source that shouldn't be, priority order picking the wrong
winner), fix the config, not just the files:

```bash
# register a directory as a lowest-priority fallback source
manage-skills sources add ~/.claude/skills Global fallback
```

Then confirm with `manage-skills locations` that the winner is the one you intended.
Fixing only the files leaves the same drift to reappear at the next edit.
