# shellcheck shell=bash

DEV_PODMAN_SOCKET="${DEV_PODMAN_SOCKET:-/run/podman/podman.sock}"
DEV_PODMAN_LOG="$HOME/.podman-socket.log"

podman_usage() {
    cat <<'EOF'
Run the podman API socket that DOCKER_HOST names, so docker, docker compose and
anything else speaking the Docker API work in this container.

  dev podman up | down | status

podman runs rootful, through sudo. An image name with no registry resolves
against docker.io. The log is ~/.podman-socket.log.
EOF
}

podman_verbs() { printf '%s\n' up down status; }

podman_running() { [ -S "$DEV_PODMAN_SOCKET" ] && pgrep -f 'podman system service' >/dev/null 2>&1; }

podman_brief() { podman_running && echo "${DOCKER_HOST:-$DEV_PODMAN_SOCKET}"; return 0; }

podman_up() {
    if podman_running; then echo "the podman socket is already listening"; return 0; fi
    sudo mkdir -p "$(dirname "$DEV_PODMAN_SOCKET")"
    # shellcheck disable=SC2024
    sudo podman system service --time=0 "unix://$DEV_PODMAN_SOCKET" \
        >> "$DEV_PODMAN_LOG" 2>&1 &
    for _ in $(seq 1 300); do
        [ -S "$DEV_PODMAN_SOCKET" ] && break
        sleep 0.1
    done
    if [ ! -S "$DEV_PODMAN_SOCKET" ]; then
        echo "podman: the socket did not appear, see $DEV_PODMAN_LOG" >&2
        return 1
    fi
    sudo chmod 666 "$DEV_PODMAN_SOCKET"
    echo "podman: listening at $DEV_PODMAN_SOCKET"
}

podman_down() {
    if ! podman_running; then echo "the podman socket is not listening"; return 0; fi
    sudo pkill -f 'podman system service' 2>/dev/null || true
    sudo rm -f "$DEV_PODMAN_SOCKET"
    echo "podman: socket stopped; images and containers are kept"
}

podman_status() {
    if ! podman_running; then
        echo "podman: socket not listening at $DEV_PODMAN_SOCKET"
        [ -s "$DEV_PODMAN_LOG" ] && tail -n 5 "$DEV_PODMAN_LOG" | sed 's/^/log: /'
        return 1
    fi
    echo "podman: listening at $DEV_PODMAN_SOCKET"
    echo "DOCKER_HOST=${DOCKER_HOST:-unset}"
    podman version --format '{{.Client.Version}}' 2>/dev/null | sed 's/^/version: /' || true
}
