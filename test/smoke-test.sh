#!/usr/bin/env bash
set -euo pipefail

# Smoke tests for manage-skills
# Compatible with bash 3.2+ (no associative arrays, no mapfile)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANAGE_SKILLS="$REPO_DIR/manage-skills"

PASS=0
FAIL=0
TESTS=0

# ── Helpers ─────────────────────────────────────────────────────────

pass() {
  PASS=$((PASS + 1))
  TESTS=$((TESTS + 1))
  echo "  ok  $1"
}

fail() {
  FAIL=$((FAIL + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL  $1"
  if [ -n "${2:-}" ]; then
    echo "        $2"
  fi
}

assert_exit() {
  local expected="$1" desc="$2"
  shift 2
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$expected" ]; then
    pass "$desc"
  else
    fail "$desc" "expected exit $expected, got $rc"
  fi
}

assert_output_contains() {
  local pattern="$1" desc="$2"
  shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -qF -- "$pattern"; then
    pass "$desc"
  else
    fail "$desc" "output missing '$pattern'"
  fi
}

# GNU stat first, BSD as fallback — same order as is_hardlinked() in the
# script. Reversed, `stat -f %i` on GNU treats %i as a filename, prints
# filesystem info to stdout and exits 1, so the fallback's real inode gets
# appended to that garbage and every inode comparison fails.
inode() {
  stat -c %i "$1" 2>/dev/null || stat -f %i "$1" 2>/dev/null
}

assert_output_matches() {
  local pattern="$1" desc="$2"
  shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -qE "$pattern"; then
    pass "$desc"
  else
    fail "$desc" "output not matching '$pattern'"
  fi
}

# ── Setup ───────────────────────────────────────────────────────────

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

export MANAGE_SKILLS_HOME="$TMPDIR_BASE/config"

SOURCE_DIR="$TMPDIR_BASE/sources/my-skills"
PROJECT_DIR="$TMPDIR_BASE/project"
mkdir -p "$SOURCE_DIR/test-skill"
mkdir -p "$PROJECT_DIR"
echo "# Test Skill" > "$SOURCE_DIR/test-skill/SKILL.md"

# ── Tests ───────────────────────────────────────────────────────────

echo "Syntax"
assert_exit 0 "bash -n manage-skills" bash -n "$MANAGE_SKILLS"

echo ""
echo "Version and help"
assert_output_contains "manage-skills" "--version output" "$MANAGE_SKILLS" --version
assert_exit 0 "--help exits cleanly" "$MANAGE_SKILLS" --help
assert_output_contains "USAGE" "--help shows usage" "$MANAGE_SKILLS" --help

echo ""
echo "Init"
assert_exit 0 "init creates config" "$MANAGE_SKILLS" init
test -d "$MANAGE_SKILLS_HOME" && pass "config dir created" || fail "config dir created"
test -f "$MANAGE_SKILLS_HOME/sources" && pass "sources file created" || fail "sources file created"
test -f "$MANAGE_SKILLS_HOME/targets" && pass "targets file created" || fail "targets file created"

echo ""
echo "Sources"
assert_exit 0 "sources add" "$MANAGE_SKILLS" sources add "$SOURCE_DIR"
assert_output_contains "$SOURCE_DIR" "sources list shows added dir" "$MANAGE_SKILLS" sources list
assert_exit 0 "sources remove" "$MANAGE_SKILLS" sources remove "$SOURCE_DIR"

# Re-add for remaining tests
"$MANAGE_SKILLS" sources add "$SOURCE_DIR" >/dev/null 2>&1

echo ""
echo "Targets"
assert_output_contains "claude" "targets list shows the claude default" "$MANAGE_SKILLS" targets list
assert_output_contains "codex" "targets list shows the codex default" "$MANAGE_SKILLS" targets list
assert_output_contains ".agents/skills" "codex target uses the shared discovery path" \
  "$MANAGE_SKILLS" targets list

echo ""
echo "List"
cd "$PROJECT_DIR"
assert_exit 0 "list exits cleanly" "$MANAGE_SKILLS" list
assert_output_contains "test-skill" "list shows test-skill" "$MANAGE_SKILLS" list

echo ""
echo "Link and unlink"
assert_exit 0 "link test-skill" "$MANAGE_SKILLS" link test-skill
test -f "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md" && pass "skill file exists after link" || fail "skill file exists after link"

# Verify hardlink (same inode)
INODE_SRC=$(inode "$SOURCE_DIR/test-skill/SKILL.md")
INODE_DST=$(inode "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md")
if [ "$INODE_SRC" = "$INODE_DST" ]; then
  pass "hardlink shares inode"
else
  fail "hardlink shares inode" "src=$INODE_SRC dst=$INODE_DST"
fi

# Codex reads .agents/skills; same hardlink mechanics, different directory.
assert_exit 0 "link into the codex target" "$MANAGE_SKILLS" link test-skill --target codex
test -f "$PROJECT_DIR/.agents/skills/test-skill/SKILL.md" \
  && pass "codex target writes to .agents/skills" || fail "codex target writes to .agents/skills"
if [ "$(inode "$SOURCE_DIR/test-skill/SKILL.md")" = "$(inode "$PROJECT_DIR/.agents/skills/test-skill/SKILL.md")" ]; then
  pass "codex target shares the inode with the source"
else
  fail "codex target shares the inode with the source"
fi
assert_exit 0 "unlink from the codex target" "$MANAGE_SKILLS" unlink test-skill --target codex

assert_exit 0 "unlink test-skill" "$MANAGE_SKILLS" unlink test-skill
test ! -d "$PROJECT_DIR/.claude/skills/test-skill" && pass "skill dir removed after unlink" || fail "skill dir removed after unlink"

echo ""
echo "Check and sync"
"$MANAGE_SKILLS" link test-skill >/dev/null 2>&1
assert_exit 0 "check exits cleanly" "$MANAGE_SKILLS" check
assert_output_matches "[0-9]+ linked" "check reports linked count" "$MANAGE_SKILLS" check

# Break the hardlink by removing and recreating as independent file
rm "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
echo "# Test Skill (modified copy)" > "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
assert_output_contains "cop" "check detects broken hardlink" "$MANAGE_SKILLS" check
assert_exit 0 "sync exits cleanly" "$MANAGE_SKILLS" sync
assert_output_contains "relinked" "sync relinks broken copy" "$MANAGE_SKILLS" sync

# After sync, check should be clean
# Re-break and re-sync to test the actual relink. The copy is identical to the
# source here — a diverging one is deliberately left alone now, see below.
rm "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
cp "$SOURCE_DIR/test-skill/SKILL.md" "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
"$MANAGE_SKILLS" sync >/dev/null 2>&1
INODE_SRC2=$(inode "$SOURCE_DIR/test-skill/SKILL.md")
INODE_DST2=$(inode "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md")
if [ "$INODE_SRC2" = "$INODE_DST2" ]; then
  pass "sync restores hardlink"
else
  fail "sync restores hardlink" "src=$INODE_SRC2 dst=$INODE_DST2"
fi

# A copy whose content still matches the source is the common case — an Edit
# tool detached the inode without changing a word. Relinking that loses nothing.
rm "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
cp "$SOURCE_DIR/test-skill/SKILL.md" "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
assert_output_contains "relinked" "sync relinks an identical copy" "$MANAGE_SKILLS" sync

# A copy whose content differs is somebody's work. Relinking would delete it, so
# sync reports it and moves on — still exit 0, because this is not a failure.
rm "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
echo "# Deliberately adapted for this project" > "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
assert_exit 0 "sync exits cleanly when content diverged" "$MANAGE_SKILLS" sync
assert_output_contains "test-skill" "sync names the diverged skill" "$MANAGE_SKILLS" sync
assert_output_contains "--force" "sync points at the flag that would overwrite" "$MANAGE_SKILLS" sync
if grep -q "Deliberately adapted" "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"; then
  pass "sync leaves diverged content alone"
else
  fail "sync leaves diverged content alone" "the local edit was overwritten"
fi

# --force is the deliberate override.
assert_output_contains "relinked" "sync --force relinks anyway" "$MANAGE_SKILLS" sync --force
INODE_SRC3=$(inode "$SOURCE_DIR/test-skill/SKILL.md")
INODE_DST3=$(inode "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md")
if [ "$INODE_SRC3" = "$INODE_DST3" ]; then
  pass "sync --force restores the hardlink"
else
  fail "sync --force restores the hardlink" "src=$INODE_SRC3 dst=$INODE_DST3"
fi

echo ""
echo "Project-owned skills"
# Regression: an original (a skill the project owns, provided by no source)
# used to abort `check` — `grep` found nothing, `set -o pipefail` turned that
# into exit 1 and `set -e` killed the run before the originals branch ever ran.
mkdir -p "$PROJECT_DIR/.claude/skills/project-original"
echo "# Original" > "$PROJECT_DIR/.claude/skills/project-original/SKILL.md"
assert_exit 0 "check survives a project-owned skill" "$MANAGE_SKILLS" check
assert_output_matches "1 originals?" "check counts the original" "$MANAGE_SKILLS" check
assert_output_contains "project-original" "list shows the original" "$MANAGE_SKILLS" list
assert_exit 0 "sync survives a project-owned skill" "$MANAGE_SKILLS" sync

echo ""
echo "Piped list output"
# Not a terminal, so `list` stays one skill per line and remains grep-able.
# (On a terminal the same skills are laid out in columns, several per line.)
LIST_OUT=$("$MANAGE_SKILLS" list)
MERGED=$(echo "$LIST_OUT" | grep "test-skill" | grep -c "project-original" || true)
if [ "$MERGED" -eq 0 ] && echo "$LIST_OUT" | grep -q "project-original"; then
  pass "piped list keeps one skill per line"
else
  fail "piped list keeps one skill per line" "skills share a line"
fi

rm -rf "$PROJECT_DIR/.claude/skills/project-original"

echo ""
echo "Locations"
assert_exit 0 "locations exits cleanly" "$MANAGE_SKILLS" locations
assert_output_contains "test-skill" "locations lists the source's skills" "$MANAGE_SKILLS" locations
assert_output_contains "$SOURCE_DIR" "locations names the source dir" "$MANAGE_SKILLS" locations

# A trailing "# label" describes the source; older label-free lines keep working.
LABELLED_DIR="$TMPDIR_BASE/sources/labelled"
mkdir -p "$LABELLED_DIR/labelled-skill"
echo "# Labelled" > "$LABELLED_DIR/labelled-skill/SKILL.md"
"$MANAGE_SKILLS" sources add "$LABELLED_DIR" Extra skills for tests >/dev/null 2>&1
assert_output_contains "Extra skills for tests" "sources list shows the label" "$MANAGE_SKILLS" sources list
assert_output_contains "Extra skills for tests" "locations shows the label" "$MANAGE_SKILLS" locations
assert_output_contains "labelled-skill" "labelled source still resolves" "$MANAGE_SKILLS" list
assert_exit 0 "link from a labelled source" "$MANAGE_SKILLS" link labelled-skill
LI_SRC=$(inode "$LABELLED_DIR/labelled-skill/SKILL.md")
LI_DST=$(inode "$PROJECT_DIR/.claude/skills/labelled-skill/SKILL.md")
if [ "$LI_SRC" = "$LI_DST" ]; then
  pass "labelled source hardlinks correctly"
else
  fail "labelled source hardlinks correctly" "src=$LI_SRC dst=$LI_DST"
fi
"$MANAGE_SKILLS" unlink labelled-skill >/dev/null 2>&1

# A second source providing the same name is shadowed by the first.
SHADOW_DIR="$TMPDIR_BASE/sources/shadow"
mkdir -p "$SHADOW_DIR/test-skill"
echo "# Shadowed" > "$SHADOW_DIR/test-skill/SKILL.md"
"$MANAGE_SKILLS" sources add "$SHADOW_DIR" Lower priority >/dev/null 2>&1
assert_output_contains "shadowed" "locations flags a shadowed skill" "$MANAGE_SKILLS" locations
"$MANAGE_SKILLS" sources remove "$SHADOW_DIR" >/dev/null 2>&1
"$MANAGE_SKILLS" sources remove "$LABELLED_DIR" >/dev/null 2>&1

# notes.md is appended verbatim when it exists.
echo "CONVENTION: kubernetes spelled out" > "$MANAGE_SKILLS_HOME/notes.md"
assert_output_contains "CONVENTION: kubernetes spelled out" "locations appends notes.md" "$MANAGE_SKILLS" locations
rm -f "$MANAGE_SKILLS_HOME/notes.md"

echo ""
echo "Config repair"
# Regression: ensure_config bailed out on an existing directory, so a config
# dir without a targets file left every command dying on "Unknown target".
BARE_HOME="$TMPDIR_BASE/bare-config"
mkdir -p "$BARE_HOME"
assert_exit 0 "init repairs a config dir with no files" env MANAGE_SKILLS_HOME="$BARE_HOME" "$MANAGE_SKILLS" init
test -f "$BARE_HOME/targets" && pass "targets file recreated" || fail "targets file recreated"

echo ""
echo "Target flag"
assert_exit 0 "list accepts --target" "$MANAGE_SKILLS" list --target claude
assert_exit 0 "list accepts a positional target" "$MANAGE_SKILLS" list claude
assert_exit 0 "locations accepts --target" "$MANAGE_SKILLS" locations --target claude
assert_exit 0 "check accepts --target" "$MANAGE_SKILLS" check --target claude
assert_exit 1 "unknown target fails" "$MANAGE_SKILLS" list --target bogus

echo ""
echo "Remote sources"
# A local repo over file:// exercises the whole path without a network.
UPSTREAM="$TMPDIR_BASE/upstream"
mkdir -p "$UPSTREAM/skills/remote-skill"
echo "# Remote v1" > "$UPSTREAM/skills/remote-skill/SKILL.md"
git -C "$UPSTREAM" init -q -b main
git -C "$UPSTREAM" add -A
git -C "$UPSTREAM" -c user.email=t@example.com -c user.name=Test commit -qm init

REMOTE_PROJECT="$TMPDIR_BASE/remote-project"
mkdir -p "$REMOTE_PROJECT"
cd "$REMOTE_PROJECT"

assert_exit 0 "sources add clones a remote" "$MANAGE_SKILLS" sources add "file://$UPSTREAM" Remote test
assert_output_contains "remote-skill" "remote skill is discoverable" "$MANAGE_SKILLS" list
assert_exit 0 "link from a remote source" "$MANAGE_SKILLS" link remote-skill

LIVE="$MANAGE_SKILLS_HOME/sources.d/upstream/remote-skill/SKILL.md"
LINKED="$REMOTE_PROJECT/.claude/skills/remote-skill/SKILL.md"
if [ "$(inode "$LIVE")" = "$(inode "$LINKED")" ]; then
  pass "remote skill hardlinks into the project"
else
  fail "remote skill hardlinks into the project"
fi
INODE_BEFORE=$(inode "$LINKED")

# Upstream moves on.
echo "# Remote v2" > "$UPSTREAM/skills/remote-skill/SKILL.md"
mkdir -p "$UPSTREAM/skills/second-skill"
echo "# Second" > "$UPSTREAM/skills/second-skill/SKILL.md"
git -C "$UPSTREAM" add -A
git -C "$UPSTREAM" -c user.email=t@example.com -c user.name=Test commit -qm v2

assert_output_contains "behind" "update --check reports pending commits" "$MANAGE_SKILLS" update --check
# --check must not change anything.
if grep -q "Remote v1" "$LINKED"; then
  pass "update --check leaves files alone"
else
  fail "update --check leaves files alone"
fi

assert_exit 0 "update pulls the remote" "$MANAGE_SKILLS" update

# The point of the whole design: the project was never touched, yet it has the
# new content, because the file was rewritten in place and the inode held.
if grep -q "Remote v2" "$LINKED"; then
  pass "update reaches the linked project without a sync"
else
  fail "update reaches the linked project without a sync" "$(cat "$LINKED")"
fi
if [ "$(inode "$LINKED")" = "$INODE_BEFORE" ]; then
  pass "update keeps the inode"
else
  fail "update keeps the inode" "was $INODE_BEFORE, now $(inode "$LINKED")"
fi
assert_output_contains "second-skill" "new upstream skill appears" "$MANAGE_SKILLS" list
assert_exit 0 "check stays clean after an update" "$MANAGE_SKILLS" check
assert_output_contains "up to date" "update is idempotent" "$MANAGE_SKILLS" update
assert_exit 1 "update on an unknown source fails" "$MANAGE_SKILLS" update no-such-source

"$MANAGE_SKILLS" sources remove "file://$UPSTREAM" >/dev/null 2>&1
cd "$PROJECT_DIR"

echo ""
echo "Self"
assert_exit 0 "self status exits cleanly" "$MANAGE_SKILLS" self
assert_output_contains "manage-skills" "self status names the script" "$MANAGE_SKILLS" self
assert_exit 0 "self install registers the shipped skills" "$MANAGE_SKILLS" self install
assert_output_contains "registered as a source" "self status confirms registration" "$MANAGE_SKILLS" self
assert_exit 1 "unknown self subcommand fails" "$MANAGE_SKILLS" self bogus
# Regression: `shorten` used "${1//$HOME/\~}", and bash 3.2 keeps that
# backslash. The literal \~ was written into the config, never expanded back,
# and the registered source silently vanished — macOS only.
if grep -q '\\~' "$MANAGE_SKILLS_HOME/sources"; then
  fail "config holds no unexpandable paths" "sources contains a literal backslash-tilde"
else
  pass "config holds no unexpandable paths"
fi
SELF_OUT=$("$MANAGE_SKILLS" self 2>&1)
case "$SELF_OUT" in
  *'\~'*) fail "shorten emits a bare tilde" "output contains a literal backslash-tilde" ;;
  *)      pass "shorten emits a bare tilde" ;;
esac
"$MANAGE_SKILLS" sources remove "$REPO_DIR/.claude/skills" >/dev/null 2>&1

echo ""
echo "Package"
PKG="$TMPDIR_BASE/publishable"
mkdir -p "$PKG/skills/shared-thing"
echo "# Shared" > "$PKG/skills/shared-thing/SKILL.md"
git -C "$PKG" init -q -b main
git -C "$PKG" remote add origin git@github.com:Someone/publishable.git

assert_exit 0 "package exits cleanly" "$MANAGE_SKILLS" package "$PKG"
test -f "$PKG/.claude-plugin/plugin.json" && pass "package writes the Claude Code manifest" || fail "package writes the Claude Code manifest"
test -f "$PKG/.codex-plugin/plugin.json" && pass "package writes the Codex manifest" || fail "package writes the Codex manifest"
# Both plugin systems read <name>/SKILL.md, so the two manifests point at one dir.
CC_SKILLS=$(grep '"skills"' "$PKG/.claude-plugin/plugin.json")
CX_SKILLS=$(grep '"skills"' "$PKG/.codex-plugin/plugin.json")
if [ "$CC_SKILLS" = "$CX_SKILLS" ]; then
  pass "both manifests point at the same skills dir"
else
  fail "both manifests point at the same skills dir" "claude=$CC_SKILLS codex=$CX_SKILLS"
fi
assert_output_contains "codex plugin add" "package shows the Codex route" "$MANAGE_SKILLS" package "$PKG"
assert_output_contains "Someone/publishable" "package derives the repo from the git remote" \
  "$MANAGE_SKILLS" package "$PKG"
assert_output_contains "sources add github:Someone/publishable" \
  "package shows the non-Claude-Code route too" "$MANAGE_SKILLS" package "$PKG"
if grep -q '"skills": "./skills"' "$PKG/.claude-plugin/plugin.json"; then
  pass "manifest points at the detected skills dir"
else
  fail "manifest points at the detected skills dir" "$(cat "$PKG/.claude-plugin/plugin.json")"
fi

# An existing manifest is somebody's work — never clobber it silently.
echo '{"name":"hand-written"}' > "$PKG/.claude-plugin/plugin.json"
rm -f "$PKG/.codex-plugin/plugin.json"
assert_output_contains "leaving it alone" "package keeps an existing manifest" \
  "$MANAGE_SKILLS" package "$PKG"
if grep -q "hand-written" "$PKG/.claude-plugin/plugin.json"; then
  pass "existing manifest survives"
else
  fail "existing manifest survives"
fi
assert_exit 0 "package --force overwrites" "$MANAGE_SKILLS" package "$PKG" --force
if grep -q "publishable" "$PKG/.claude-plugin/plugin.json"; then
  pass "--force rewrites the manifest"
else
  fail "--force rewrites the manifest"
fi

# Layout detection: .claude/skills works the same as skills/.
PKG2="$TMPDIR_BASE/publishable2"
mkdir -p "$PKG2/.claude/skills/other-thing"
echo "# Other" > "$PKG2/.claude/skills/other-thing/SKILL.md"
assert_exit 0 "package detects .claude/skills" "$MANAGE_SKILLS" package "$PKG2"
if grep -q '"skills": "./.claude/skills"' "$PKG2/.claude-plugin/plugin.json"; then
  pass "manifest points at .claude/skills"
else
  fail "manifest points at .claude/skills" "$(cat "$PKG2/.claude-plugin/plugin.json")"
fi

# A skill set that groups its skills one directory deeper — Getty/skills/perl/…,
# mattpocock/skills/engineering/… — is the ordinary shape for a monorepo of
# skills. The groups are organisation in the source repo only: a project links
# skills by name, so manage-skills flattens them into one level.
PKG3="$TMPDIR_BASE/grouped"
mkdir -p "$PKG3/perl/perl-core" "$PKG3/perl/perl-moose" "$PKG3/bash/bash-strict"
echo "# core" > "$PKG3/perl/perl-core/SKILL.md"
echo "# moose" > "$PKG3/perl/perl-moose/SKILL.md"
echo "# strict" > "$PKG3/bash/bash-strict/SKILL.md"
assert_exit 0 "package finds skills grouped one level deeper" "$MANAGE_SKILLS" package "$PKG3"
assert_output_contains "perl-core" "grouped: names a skill from the first group" \
  "$MANAGE_SKILLS" package "$PKG3" --force
assert_output_contains "bash-strict" "grouped: reaches every group" \
  "$MANAGE_SKILLS" package "$PKG3" --force

# The manifest paths have to be clean: a "././perl/perl-core" is valid JSON and
# a broken path.
if grep -q '"\./perl/perl-core"' "$PKG3/.claude-plugin/plugin.json"; then
  pass "grouped: manifest paths are normalised"
else
  fail "grouped: manifest paths are normalised" "$(grep skills "$PKG3/.claude-plugin/plugin.json")"
fi

# Two groups may not offer the same skill name: the copy in sources.d/ is flat,
# so one would silently overwrite the other.
PKG4="$TMPDIR_BASE/colliding"
mkdir -p "$PKG4/perl/core" "$PKG4/bash/core"
echo "# perl core" > "$PKG4/perl/core/SKILL.md"
echo "# bash core" > "$PKG4/bash/core/SKILL.md"
assert_exit 1 "package refuses a name that two groups both provide" "$MANAGE_SKILLS" package "$PKG4"
assert_output_contains "core" "collision report names the skill" "$MANAGE_SKILLS" package "$PKG4"

# One level deeper, not arbitrarily deep: a SKILL.md buried further down is more
# likely an example or a fixture than a skill someone meant to publish.
PKG5="$TMPDIR_BASE/toodeep"
mkdir -p "$PKG5/a/b/c/skill"
echo "# x" > "$PKG5/a/b/c/skill/SKILL.md"
assert_exit 1 "package does not search arbitrarily deep" "$MANAGE_SKILLS" package "$PKG5"

assert_exit 1 "package fails on a directory with no skills" "$MANAGE_SKILLS" package "$TMPDIR_BASE"

# The remote path materialises a checkout into sources.d/ — and that is where a
# grouped set has to end up flat, because link/list/sync all read that directory.
if command -v git >/dev/null 2>&1; then
  GROUPED_REPO="$TMPDIR_BASE/grouped-repo"
  mkdir -p "$GROUPED_REPO/perl/perl-core" "$GROUPED_REPO/k8s/k8s-basics"
  echo "# core" > "$GROUPED_REPO/perl/perl-core/SKILL.md"
  echo "# k8s" > "$GROUPED_REPO/k8s/k8s-basics/SKILL.md"
  (
    cd "$GROUPED_REPO"
    git init -q .
    git -c user.email=t@example.com -c user.name=Test add -A
    git -c user.email=t@example.com -c user.name=Test commit -qm "grouped skills"
  ) >/dev/null 2>&1

  assert_exit 0 "remote source with grouped skills adds cleanly" \
    "$MANAGE_SKILLS" sources add "file://$GROUPED_REPO"
  assert_output_contains "perl-core" "grouped remote: list shows a skill from one group" \
    "$MANAGE_SKILLS" list
  assert_output_contains "k8s-basics" "grouped remote: list shows the other group too" \
    "$MANAGE_SKILLS" list
  if [ -f "$MANAGE_SKILLS_HOME/sources.d/grouped-repo/perl-core/SKILL.md" ] &&
     [ -f "$MANAGE_SKILLS_HOME/sources.d/grouped-repo/k8s-basics/SKILL.md" ]; then
    pass "grouped remote: materialises flat into sources.d"
  else
    fail "grouped remote: materialises flat into sources.d" \
      "$(ls "$MANAGE_SKILLS_HOME/sources.d/grouped-repo" 2>&1)"
  fi
  assert_exit 0 "grouped remote: a skill from a group links" "$MANAGE_SKILLS" link perl-core
  "$MANAGE_SKILLS" sources remove "file://$GROUPED_REPO" >/dev/null 2>&1 || true
else
  echo "  skip  grouped remote source (git not available)"
fi

echo ""
echo "Grouped local source"
# A local directory groups its skills one level deep, exactly like a checkout —
# discovery has to go through the same detection, not a flat glob.
GROUPED_LOCAL="$TMPDIR_BASE/grouped-local"
mkdir -p "$GROUPED_LOCAL/perl/grouped-perl-skill" "$GROUPED_LOCAL/k8s/grouped-k8s-skill"
echo "# perl" > "$GROUPED_LOCAL/perl/grouped-perl-skill/SKILL.md"
echo "# k8s" > "$GROUPED_LOCAL/k8s/grouped-k8s-skill/SKILL.md"
"$MANAGE_SKILLS" sources add "$GROUPED_LOCAL" Grouped local >/dev/null 2>&1

assert_output_contains "grouped-perl-skill" "grouped local: list shows a skill from one group" \
  "$MANAGE_SKILLS" list
assert_output_contains "grouped-k8s-skill" "grouped local: list shows the other group too" \
  "$MANAGE_SKILLS" list
assert_output_contains "grouped-perl-skill" "grouped local: locations shows a skill from a group" \
  "$MANAGE_SKILLS" locations
assert_exit 0 "grouped local: a skill from a group links" "$MANAGE_SKILLS" link grouped-perl-skill
if [ "$(inode "$PROJECT_DIR/.claude/skills/grouped-perl-skill/SKILL.md" 2>/dev/null)" = \
     "$(inode "$GROUPED_LOCAL/perl/grouped-perl-skill/SKILL.md")" ]; then
  pass "grouped local: link shares the source inode"
else
  fail "grouped local: link shares the source inode"
fi
"$MANAGE_SKILLS" unlink grouped-perl-skill >/dev/null 2>&1 || true
"$MANAGE_SKILLS" sources remove "$GROUPED_LOCAL" >/dev/null 2>&1 || true

echo ""
echo "Packaging consistency"
# The version lives in the script and the plugin manifest; the release
# workflow bumps both.
SCRIPT_VERSION=$(grep -m1 '^VERSION=' "$MANAGE_SKILLS" | cut -d'"' -f2)
PLUGIN_VERSION=$(grep -m1 '"version"' "$REPO_DIR/.claude-plugin/plugin.json" | cut -d'"' -f4)
if [ "$SCRIPT_VERSION" = "$PLUGIN_VERSION" ]; then
  pass "version matches between script and plugin manifest"
else
  fail "version matches between script and plugin manifest" \
       "script=$SCRIPT_VERSION plugin=$PLUGIN_VERSION"
fi

# This repo ships to Codex as well, from the same skills directory. The release
# workflow only knows about the two files it rewrites, so a third manifest that
# drifts out of step would ship a wrong version to half the users.
test -f "$REPO_DIR/.codex-plugin/plugin.json" \
  && pass "Codex manifest exists" || fail "Codex manifest exists"
CODEX_VERSION=$(grep -m1 '"version"' "$REPO_DIR/.codex-plugin/plugin.json" 2>/dev/null | cut -d'"' -f4)
if [ "$SCRIPT_VERSION" = "$CODEX_VERSION" ]; then
  pass "version matches between script and Codex manifest"
else
  fail "version matches between script and Codex manifest" \
       "script=$SCRIPT_VERSION codex=$CODEX_VERSION"
fi
# `"skills"` also appears in the keyword list, so match the key, not the word.
CLAUDE_SKILLS_PATH=$(grep -m1 '"skills":' "$REPO_DIR/.claude-plugin/plugin.json" | cut -d'"' -f4)
CODEX_SKILLS_PATH=$(grep -m1 '"skills":' "$REPO_DIR/.codex-plugin/plugin.json" 2>/dev/null | cut -d'"' -f4)
if [ "$CLAUDE_SKILLS_PATH" = "$CODEX_SKILLS_PATH" ]; then
  pass "both manifests point at the same skills directory"
else
  fail "both manifests point at the same skills directory" \
       "claude=$CLAUDE_SKILLS_PATH codex=$CODEX_SKILLS_PATH"
fi

# SELF_SKILLS is hand-maintained; it must match what .claude/skills actually holds.
DECLARED=$(grep -m1 '^SELF_SKILLS=' "$MANAGE_SKILLS" | cut -d'"' -f2 | tr ' ' '\n' | sort | tr '\n' ' ')
ON_DISK=$(for d in "$REPO_DIR"/.claude/skills/*/; do
            [ -f "$d/SKILL.md" ] && basename "$d"
          done | sort | tr '\n' ' ')
if [ "$DECLARED" = "$ON_DISK" ]; then
  pass "SELF_SKILLS matches .claude/skills"
else
  fail "SELF_SKILLS matches .claude/skills" "declared='$DECLARED' on disk='$ON_DISK'"
fi

# bin/manage-skills goes on the Bash tool's PATH when the plugin is enabled.
if [ -L "$REPO_DIR/bin/manage-skills" ] && [ -x "$REPO_DIR/bin/manage-skills" ]; then
  pass "bin/manage-skills is a working relative symlink"
else
  fail "bin/manage-skills is a working relative symlink"
fi

echo ""
echo "Error handling"
assert_exit 1 "unknown command fails" "$MANAGE_SKILLS" bogus-command
assert_exit 1 "link without args fails" "$MANAGE_SKILLS" link
# Regression: `shift 2` past the end shifted nothing, so arg parsing spun forever.
assert_exit 1 "dangling --target fails instead of hanging" "$MANAGE_SKILLS" list --target
assert_exit 1 "dangling --target on link fails" "$MANAGE_SKILLS" link some-skill --target

# ── Summary ─────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────"
echo "$TESTS tests, $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
