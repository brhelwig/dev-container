# shellcheck shell=bash

DEV_CODE="${DEV_CODE:-/usr/local/bin/code}"
DEV_CODE_LOG="$HOME/.code-tunnel.log"

code_usage() {
    cat <<'EOF'
Run a VS Code Remote Tunnel from this container, so it can be opened in VS Code
from any machine signed in to the same account.

  dev code login | up | down | status

The tunnel dials out to the VS Code tunnel service, so nothing listens in the
container and no port has to be published. Sign in once with "dev code login";
the credentials and the server the CLI downloads live under ~/.vscode, which
persists, so every later launch starts the tunnel on its own.

The tunnel is named after the hostname. The log is ~/.code-tunnel.log.
EOF
}

code_verbs() { printf '%s\n' login up down status; }

code_name() {
    local name
    name="$(hostname)"
    name="${name//[^a-zA-Z0-9-]/-}"
    printf '%s\n' "${name,,}"
}

code_signed_in() { "$DEV_CODE" tunnel user show >/dev/null 2>&1; }

code_running() {
    "$DEV_CODE" tunnel status 2>/dev/null | python3 -c '
import json, sys
try:
    sys.exit(0 if json.load(sys.stdin).get("tunnel") else 1)
except (json.JSONDecodeError, AttributeError):
    sys.exit(1)
'
}

code_brief() {
    if code_running; then
        code_name
    elif ! code_signed_in; then
        echo "not signed in"
    fi
}

code_login() {
    "$DEV_CODE" tunnel user login "$@"
    echo "signed in; start the tunnel with: dev code up"
}

code_up() {
    if code_running; then echo "the tunnel is already running"; return 0; fi
    if ! code_signed_in; then
        echo "Not signed in to the VS Code tunnel service." >&2
        echo "Sign in once with: dev code login" >&2
        return 1
    fi
    local name
    name="$(code_name)"
    setsid nohup "$DEV_CODE" tunnel \
        --accept-server-license-terms \
        --name "$name" \
        >> "$DEV_CODE_LOG" 2>&1 < /dev/null &
    echo "code: tunnel '$name' starting; watch it with: dev code status"
}

code_down() {
    "$DEV_CODE" tunnel kill
    echo "code: tunnel stopped; the sign-in is kept"
}

code_status() {
    if ! code_running; then
        echo "code: tunnel not running"
        code_signed_in || echo "not signed in — run: dev code login"
        [ -s "$DEV_CODE_LOG" ] && tail -n 5 "$DEV_CODE_LOG" | sed 's/^/log: /'
        return 1
    fi
    echo "code: tunnel running as '$(code_name)'"
    local url
    url="$(grep -oE 'https://[^ ]*tunnel[^ ]*' "$DEV_CODE_LOG" 2>/dev/null | tail -1)" || true
    if [ -n "$url" ]; then
        echo "open: $url"
    else
        echo "no connection link in $DEV_CODE_LOG yet"
    fi
}
