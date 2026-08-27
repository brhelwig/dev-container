#!/usr/bin/env bash
set -uo pipefail

AUTH_KEYS="$HOME/.ssh/authorized_keys"

seed_home() {
    [ -e "$HOME/.seeded" ] && return 0
    cp -a /etc/skel/. "$HOME/" 2>/dev/null || true
    touch "$HOME/.seeded"
}

seed_authorized_keys() {
    [ -n "${SSH_AUTHORIZED_KEYS:-}" ] || return 0
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$AUTH_KEYS"
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        grep -qxF "$key" "$AUTH_KEYS" 2>/dev/null || printf '%s\n' "$key" >> "$AUTH_KEYS"
    done <<< "$SSH_AUTHORIZED_KEYS"
    chmod 600 "$AUTH_KEYS"
}

configure_docker_cli() {
    local cfg="$HOME/.docker/config.json"
    [ -s "$cfg" ] && return 0
    mkdir -p "$HOME/.docker"
    printf '{\n  "cliPluginsExtraDirs": ["/home/linuxbrew/.linuxbrew/lib/docker/cli-plugins"]\n}\n' > "$cfg"
}

start_zellij() {
    local session
    session="$(hostname)"
    zellij attach --create-background "$session" \
        || echo "zellij: failed to create session '$session'" >&2
}

seed_home
seed_authorized_keys
configure_docker_cli
dev ssh up
dev ts up
dev podman up
dev code up
start_zellij

exec "$@"
