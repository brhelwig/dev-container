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
    local tailscaled state_dir
    tailscaled="$(command -v tailscaled)"
    state_dir="$HOME/.tailscale"
    mkdir -p "$state_dir"
    chmod 700 "$state_dir"
    sudo "$tailscaled" --statedir="$state_dir" \
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

configure_docker_cli() {
    local cfg="$HOME/.docker/config.json"
    [ -s "$cfg" ] && return 0
    mkdir -p "$HOME/.docker"
    printf '{\n  "cliPluginsExtraDirs": ["/home/linuxbrew/.linuxbrew/lib/docker/cli-plugins"]\n}\n' > "$cfg"
}

start_podman_socket() {
    local sock_dir="/run/podman"
    local sock_path="$sock_dir/podman.sock"
    sudo mkdir -p "$sock_dir"
    sudo podman system service --time=0 "unix://$sock_path" \
        >> "$HOME/.podman-socket.log" 2>&1 &
    for _ in $(seq 1 50); do
        [ -S "$sock_path" ] && break
        sleep 0.1
    done
    sudo chmod 666 "$sock_path"
    echo "podman socket: listening at $sock_path"
}

seed_home
seed_authorized_keys
configure_docker_cli
start_sshd
start_tailscale
start_podman_socket
start_vscode_tunnel
start_zellij

exec "$@"
