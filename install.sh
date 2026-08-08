#!/bin/sh
set -eu

# reposync installer: copies the script to ~/.local/bin, writes a default
# config, and installs systemd user units (warn timer, sync timer, session
# end). Pure user-space: no sudo, nothing outside $HOME and systemd --user.

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_root=${XDG_BIN_HOME:-"$HOME/.local/bin"}
config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}/reposync
unit_root=$HOME/.config/systemd/user

mkdir -p "$bin_root" "$config_root" "$unit_root"

install -m 0755 "$repo_root/reposync" "$bin_root/reposync"

if [ ! -f "$config_root/config" ]; then
    sed "s|^repo_root=.*|repo_root=$HOME/Documents/github|" \
        "$repo_root/reposync.conf.example" > "$config_root/config"
    printf 'created %s\n' "$config_root/config"
fi

for name in reposync-warn.service reposync-warn.timer \
            reposync-sync.service reposync-sync.timer \
            reposync-session-end.service; do
    unit="$repo_root/systemd/$name"
    [ -f "$unit" ] || continue
    sed "s|%BIN%|$bin_root/reposync|g" "$unit" > "$unit_root/$name"
    printf 'installed %s\n' "$unit_root/$name"
done

printf '%s\n' "Installed reposync to $bin_root/reposync"
printf '%s\n' "Enable with: systemctl --user daemon-reload && systemctl --user enable --now reposync-warn.timer reposync-sync.timer"
