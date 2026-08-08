# reposync

Declarative multi-repo sync and dirty-work guard for people who keep all their
repositories in one directory. Used by the LinuxMice fleet as the always-on
git hygiene watchdog.

**It never commits. It never pushes.** reposync fetches remote refs and warns
when local work has been uncommitted or unpushed for too long. The operator
always decides what happens.

## What it does

- `status` — table of every repo under the configured roots: worktree state,
  unpushed
  commit count, age of the last local work.
- `warn` — checks (fully offline) for work older than `stale_hours` that is
  uncommitted or unpushed, and raises a notification. Per-repo cooldown
  prevents nagging.
- `sync` — `git fetch --prune origin` for every repo with a remote, throttled
  per repo so GitHub never sees a burst. Never touches the worktree.
- `install` — installs the script, config, and systemd user units.

Timers (systemd user units):

| Unit | Schedule | Runs |
|---|---|---|
| `reposync-warn.timer` | hourly | `reposync warn` (offline) |
| `reposync-sync.timer` | every 6 h | `reposync sync` (throttled) |
| `reposync-session-end.service` | at logout/shutdown | `reposync warn` |

## Install

```sh
./install.sh
systemctl --user daemon-reload
systemctl --user enable --now reposync-warn.timer reposync-sync.timer
# optional: systemctl --user enable reposync-session-end.service
```

Pure user-space: no root, nothing leaves `$HOME`.

## Config

`~/.config/reposync/config` (created by `install`):

```ini
repo_root=$HOME/Documents/github
# repo_root_append=$HOME/Documents/gitlab
# repo_root_append=$HOME/Documents/forgejo
stale_hours=8
fetch_min_hours=6
notify_cooldown_hours=24
# notify_command=notify-send -u normal
```

Multiple repository roots are supported: add one `repo_root_append=` line per
extra directory (for example GitHub, GitLab, and Forgejo checkouts). Overridable
at runtime via `REPOSYNC_CONFIG` and `REPOSYNC_STATE_ROOT` (used by the test
suite).

## Design notes

- **Offline guard first**: `warn` never opens a network connection, so the
  hourly timer is safe on battery, in meetings, and in offline trains.
- **Throttled fetch**: per-repo state file records the last fetch; repos are
  only fetched after `fetch_min_hours`. No burst, no API abuse.
- **Operator decides**: warnings carry the repo name, age, and cooldown state.
  There is no auto-commit and no auto-push, by design.
- **Failure of one repo never fails the run**: every `git` call is guarded.

## Requirements

- bash, git, and (optionally) `notify-send` or a `notify_command` for
  desktop notifications.

## Test

```sh
bash tests/smoke.sh
```

The suite is fully offline and exercises clean, dirty, unpushed, and
remote-backed repos plus the fetch throttle and notification path.

## License

MIT. See [LICENSE](LICENSE).
