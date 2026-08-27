# shellcheck shell=bash

DEV_SSHD="${DEV_SSHD:-/usr/sbin/sshd}"
DEV_SSHD_CONFIG="${DEV_SSHD_CONFIG:-/etc/ssh/dev-container-sshd.conf}"
DEV_SSHD_PRIVSEP_DIR="${DEV_SSHD_PRIVSEP_DIR:-/run/sshd}"
DEV_SSHD_PID_FILE="${DEV_SSHD_PID_FILE:-/run/dev-sshd.pid}"
DEV_SSH_KEY_DIR="$HOME/.ssh-host-keys"
DEV_SSH_HOST_KEY="$DEV_SSH_KEY_DIR/ssh_host_ed25519_key"
DEV_SSH_KEYS="$HOME/.ssh/authorized_keys"
DEV_SSH_PORT_FILE="$HOME/.sandbox-ssh-port"
DEV_SSH_LOG="$HOME/.sshd.log"

ssh_usage() {
    cat <<'EOF'
Run an SSH server in this container, so it can be reached with ssh, and with
scp, rsync, and everything else built on it.

  dev ssh up | down | status

The server listens on port 22 inside the container. How that port is reached
depends on how the container was launched: a published port, the tailnet
address when tailscale is up, or the pod address under the Helm chart. Only a
key in ~/.ssh/authorized_keys gets in; passwords and root logins are refused,
and the server refuses to start while no key is authorized.

The host key lives in ~/.ssh-host-keys. The home persists, so the fingerprint
survives container recreation and image rebuilds. The log is ~/.sshd.log.
EOF
}

ssh_verbs() { printf '%s\n' up down status; }

ssh_running() {
    local pid
    pid="$(cat "$DEV_SSHD_PID_FILE" 2>/dev/null || true)"
    [ -n "$pid" ] || return 1
    grep -qx sshd "/proc/$pid/comm" 2>/dev/null
}

ssh_key_count() {
    local count
    count="$(grep -cE '^[[:space:]]*[^#[:space:]]' "$DEV_SSH_KEYS" 2>/dev/null || true)"
    printf '%s\n' "${count:-0}"
}

ssh_authorized() { [ "$(ssh_key_count)" -gt 0 ]; }

ssh_no_keys() {
    echo "No authorized key, so nothing could log in." >&2
    echo "Add a public key to $DEV_SSH_KEYS, one key to a line, or set" >&2
    echo "SSH_AUTHORIZED_KEYS in the environment and restart the container." >&2
}

ssh_report_reach() {
    local port user addr
    user="$(id -un)"
    port="$(cat "$DEV_SSH_PORT_FILE" 2>/dev/null || true)"
    if [ -n "$port" ]; then
        echo "from the host: ssh -p $port $user@127.0.0.1"
    else
        echo "listening on port 22 inside the container"
    fi
    addr="$(tailscale ip -4 2>/dev/null | head -1 || true)"
    [ -n "$addr" ] && echo "over the tailnet: ssh $user@$addr"
    return 0
}

ssh_brief() {
    if ssh_running; then
        echo "$(ssh_key_count) authorized key(s)"
    elif ! ssh_authorized; then
        echo "no authorized key"
    fi
}

ssh_ensure_host_key() {
    mkdir -p "$DEV_SSH_KEY_DIR"
    chmod 700 "$DEV_SSH_KEY_DIR"
    [ -s "$DEV_SSH_HOST_KEY" ] && return 0
    ssh-keygen -q -t ed25519 -N '' -C "dev-container $(hostname)" -f "$DEV_SSH_HOST_KEY"
}

ssh_up() {
    if ssh_running; then echo "the SSH server is already running"; return 0; fi
    if ! ssh_authorized; then
        ssh_no_keys
        return 1
    fi
    ssh_ensure_host_key
    : >> "$DEV_SSH_LOG"
    sudo mkdir -p "$DEV_SSHD_PRIVSEP_DIR"
    sudo chmod 0755 "$DEV_SSHD_PRIVSEP_DIR"
    sudo "$DEV_SSHD" -f "$DEV_SSHD_CONFIG" -h "$DEV_SSH_HOST_KEY" \
        -o "PidFile=$DEV_SSHD_PID_FILE" -E "$DEV_SSH_LOG"
    echo "ssh: listening on port 22"
    ssh_report_reach
}

ssh_down() {
    if ! ssh_running; then echo "the SSH server is not running"; return 0; fi
    sudo kill "$(cat "$DEV_SSHD_PID_FILE")"
    sudo rm -f "$DEV_SSHD_PID_FILE"
    echo "ssh: stopped; the host key and the authorized keys are kept"
}

ssh_status() {
    if ! ssh_running; then
        echo "ssh: not running"
        ssh_authorized || ssh_no_keys
        [ -s "$DEV_SSH_LOG" ] && tail -n 5 "$DEV_SSH_LOG" | sed 's/^/log: /'
        return 1
    fi
    echo "ssh: running, $(ssh_key_count) authorized key(s)"
    ssh_report_reach
}
