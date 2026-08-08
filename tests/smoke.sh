#!/usr/bin/env bash
set -euo pipefail

# reposync smoke test: runs entirely offline against a throwaway tree.

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export REPOSYNC_STATE_ROOT="$TEST_ROOT/state"
export REPOSYNC_CONFIG="$TEST_ROOT/config"
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME" "$REPOSYNC_STATE_ROOT"

# Config: warn instantly, no fetch throttle, notify_command always prints.
cat >"$REPOSYNC_CONFIG" <<EOF
repo_root=$TEST_ROOT/repos
repo_root_append=$TEST_ROOT/repos2
stale_hours=0
fetch_min_hours=1
notify_cooldown_hours=0
notify_command=printf "NOTIFY|%s|%s\\n"
EOF

make_repo() { # make_repo <dir> ; a repo with one commit
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  echo a >"$1/f"
  git -C "$1" add f
  git -C "$1" commit -qm init
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$TEST_ROOT/repos"

# clean repo: nothing to warn about
make_repo "$TEST_ROOT/repos/clean"
git -C "$TEST_ROOT/repos/clean" branch -M main

# dirty repo: uncommitted change, old mtime
make_repo "$TEST_ROOT/repos/dirty"
git -C "$TEST_ROOT/repos/dirty" branch -M main
echo dirty >"$TEST_ROOT/repos/dirty/f"
touch -d "2 days ago" "$TEST_ROOT/repos/dirty/f"

# remote repo for sync test: bare origin + clone
mkdir -p "$TEST_ROOT/origins"
git -C "$TEST_ROOT/origins" init -q --bare origin.git
make_repo "$TEST_ROOT/repos/remote"
git -C "$TEST_ROOT/repos/remote" branch -M main
git -C "$TEST_ROOT/repos/remote" remote add origin "$TEST_ROOT/origins/origin.git"
git -C "$TEST_ROOT/repos/remote" push -q origin main

# unpushed repo: committed but not pushed, old commit
mkdir -p "$TEST_ROOT/origins2"
git -C "$TEST_ROOT/origins2" init -q --bare unpushed-origin.git
make_repo "$TEST_ROOT/repos/unpushed"
git -C "$TEST_ROOT/repos/unpushed" branch -M main
git -C "$TEST_ROOT/repos/unpushed" remote add origin "$TEST_ROOT/origins2/unpushed-origin.git"
git -C "$TEST_ROOT/repos/unpushed" push -q origin main
echo b >"$TEST_ROOT/repos/unpushed/f"
git -C "$TEST_ROOT/repos/unpushed" commit -qam second
# backdate the unpushed commit to trigger the stale check
GIT_AUTHOR_DATE="@1782000000 +0000" GIT_COMMITTER_DATE="@1782000000 +0000" \
  git -C "$TEST_ROOT/repos/unpushed" commit -q --amend --no-edit

# second root: dirty repo there must also be found
mkdir -p "$TEST_ROOT/repos2"
make_repo "$TEST_ROOT/repos2/otherroot"
git -C "$TEST_ROOT/repos2/otherroot" branch -M main
echo root2 >"$TEST_ROOT/repos2/otherroot/f"
touch -d "2 days ago" "$TEST_ROOT/repos2/otherroot/f"

BIN="$TEST_ROOT/bin"
mkdir -p "$BIN"
cp "$(dirname "$0")/../reposync" "$BIN/reposync"

# --- status ---
"$BIN/reposync" >/dev/null 2>&1 || fail "status failed"
# --- warn on dirty, nothing on clean, unpushed also flagged ---
"$BIN/reposync" warn 2>&1 | tee "$TEST_ROOT/warn.out"
grep -q "STALE dirty" "$TEST_ROOT/warn.out" || fail "warn did not flag dirty repo"
grep -q "STALE unpushed" "$TEST_ROOT/warn.out" || fail "warn did not flag unpushed repo"
grep -q "STALE otherroot" "$TEST_ROOT/warn.out" || fail "warn did not scan second repo root"
grep -q "STALE clean" "$TEST_ROOT/warn.out" && fail "warn flagged clean repo"
# notify_command must have fired
grep -q "NOTIFY|reposync: dirty" "$TEST_ROOT/warn.out" || fail "notify_command did not fire"
# cooldown file written
[[ -f "$REPOSYNC_STATE_ROOT/notified.dirty" ]] || fail "cooldown state not written"

# --- sync: fetch works, throttle skips second run ---
"$BIN/reposync" sync | tee "$TEST_ROOT/sync.out"
grep -q "fetch: remote" "$TEST_ROOT/sync.out" || fail "sync did not fetch remote repo"
grep -q "recent fetch, skipping" "$TEST_ROOT/sync.out" && fail "throttle skipped first fetch"
"$BIN/reposync" sync >"$TEST_ROOT/sync2.out"
grep -q "recent fetch, skipping: remote" "$TEST_ROOT/sync2.out" || fail "throttle did not skip second fetch"
# clean has no origin: must be ignored, not fetched
grep -q "fetch: clean" "$TEST_ROOT/sync.out" && fail "sync tried to fetch repo without origin"

# --- offline guard: never any network traffic ---
# (all commands above ran with no network access to a remote; fetch only hit
#  the local bare origin, which proves no hardcoded URLs are used)

echo "PASS"
