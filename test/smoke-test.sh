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
  if echo "$output" | grep -qF "$pattern"; then
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
assert_output_contains "claude" "targets list shows default" "$MANAGE_SKILLS" targets list

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
# Re-break and re-sync to test the actual relink
rm "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
echo "# Test Skill (modified copy)" > "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md"
"$MANAGE_SKILLS" sync >/dev/null 2>&1
INODE_SRC2=$(inode "$SOURCE_DIR/test-skill/SKILL.md")
INODE_DST2=$(inode "$PROJECT_DIR/.claude/skills/test-skill/SKILL.md")
if [ "$INODE_SRC2" = "$INODE_DST2" ]; then
  pass "sync restores hardlink"
else
  fail "sync restores hardlink" "src=$INODE_SRC2 dst=$INODE_DST2"
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
echo "Self"
assert_exit 0 "self status exits cleanly" "$MANAGE_SKILLS" self
assert_output_contains "manage-skills" "self status names the script" "$MANAGE_SKILLS" self
assert_exit 0 "self install registers the shipped skills" "$MANAGE_SKILLS" self install
assert_output_contains "registered as a source" "self status confirms registration" "$MANAGE_SKILLS" self
assert_exit 1 "unknown self subcommand fails" "$MANAGE_SKILLS" self bogus
"$MANAGE_SKILLS" sources remove "$REPO_DIR/.claude/skills" >/dev/null 2>&1

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
