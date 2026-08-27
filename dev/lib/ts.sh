# shellcheck shell=bash

DEV_TS_STATE_DIR="$HOME/.tailscale"
DEV_TS_LOG="$HOME/.tailscaled.log"

ts_usage() {
    cat <<'EOF'
Run tailscale in this container, so it joins your tailnet under its own name.

  dev ts up | down | status

"up" starts the daemon, and then brings the node up when TS_AUTHKEY is set in
the environment. Without a key the daemon still starts, and "sudo tailscale up"
connects the node by hand. The node is named after the hostname.

State lives in ~/.tailscale, which persists, so the node keeps its identity
across container recreation. The log is ~/.tailscaled.log.
EOF
}

ts_verbs() { printf '%s\n' up down status; }

ts_running() { pgrep -x tailscaled >/dev/null 2>&1; }

ts_brief() {
    ts_running || return 0
    local addr
    addr="$(tailscale ip -4 2>/dev/null | head -1 || true)"
    [ -n "$addr" ] && echo "$addr" || echo "daemon up, node not connected"
}

ts_up() {
    if ts_running; then
        echo "tailscaled is already running"
    else
        mkdir -p "$DEV_TS_STATE_DIR"
        chmod 700 "$DEV_TS_STATE_DIR"
        sudo "$(command -v tailscaled)" --statedir="$DEV_TS_STATE_DIR" \
            >> "$DEV_TS_LOG" 2>&1 &
        sleep 1
        echo "tailscale: daemon started"
    fi
    if [ -n "${TS_AUTHKEY:-}" ]; then
        sudo "$(command -v tailscale)" up --authkey="$TS_AUTHKEY" --hostname="$(hostname)" \
            || echo "tailscale: 'tailscale up' failed, see $DEV_TS_LOG" >&2
    else
        echo "tailscale: no TS_AUTHKEY; run 'sudo tailscale up' to connect this node"
    fi
}

ts_down() {
    if ! ts_running; then echo "tailscaled is not running"; return 0; fi
    sudo tailscale down 2>/dev/null || true
    sudo pkill -x tailscaled 2>/dev/null || true
    echo "tailscale: stopped; the node state in $DEV_TS_STATE_DIR is kept"
}

ts_status() {
    if ! ts_running; then
        echo "tailscale: not running"
        [ -s "$DEV_TS_LOG" ] && tail -n 5 "$DEV_TS_LOG" | sed 's/^/log: /'
        return 1
    fi
    tailscale status 2>&1 | sed 's/^/tailscale: /'
}
