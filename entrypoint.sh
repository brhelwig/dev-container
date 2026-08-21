#!/usr/bin/env bash
set -uo pipefail

CONFIG="/etc/ssh/dev-container-sshd.conf"
HOST_KEY_DIR="$HOME/.ssh-host-keys"
HOST_KEY="$HOST_KEY_DIR/ssh_host_ed25519_key"
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

start_sshd() {
    mkdir -p "$HOST_KEY_DIR"
    chmod 700 "$HOST_KEY_DIR"
    [ -s "$HOST_KEY" ] || ssh-keygen -q -t ed25519 -N '' -f "$HOST_KEY"
    sudo mkdir -p /run/sshd
    sudo chmod 0755 /run/sshd
    sudo /usr/sbin/sshd -f "$CONFIG" -h "$HOST_KEY"
    echo "sshd: listening on port 22"
}

start_tailscale() {
    # sudo resets PATH to its secure_path default, which doesn't include
    # Homebrew's bin dir, so resolve these before invoking sudo.
    local tailscaled
    tailscaled="$(command -v tailscaled)"
    sudo mkdir -p /var/lib/tailscale
    sudo "$tailscaled" --state=/var/lib/tailscale/tailscaled.state \
        >> "$HOME/.tailscaled.log" 2>&1 &

    if [ -n "${TS_AUTHKEY:-}" ]; then
        sleep 1
        local tailscale
        tailscale="$(command -v tailscale)"
        sudo "$tailscale" up --authkey="$TS_AUTHKEY" --hostname="$(hostname)" \
            || echo "tailscale: 'tailscale up' failed, see $HOME/.tailscaled.log" >&2
    else
        echo "tailscale: daemon started; run 'sudo tailscale up' to connect this node"
    fi
}

start_vscode_tunnel() {
    if ! code tunnel user show >/dev/null 2>&1; then
        echo "vscode tunnel: not signed in, skipping (run: code tunnel user login)"
        return 0
    fi
    setsid nohup code tunnel --accept-server-license-terms --name "$(hostname)" \
        >> "$HOME/.code-tunnel.log" 2>&1 < /dev/null &
    echo "vscode tunnel: starting in the background"
}

start_zellij() {
    zellij attach --create-background dev \
        || echo "zellij: failed to create session 'dev'" >&2
}

seed_home
seed_authorized_keys
start_sshd
start_tailscale
start_vscode_tunnel
start_zellij

exec "$@"
