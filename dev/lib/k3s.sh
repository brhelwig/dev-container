# shellcheck shell=bash

DEV_K3S_DISK="${DEV_K3S_DISK:-8G}"
DEV_K3S_NODE_IP="${DEV_K3S_NODE_IP:-10.99.0.1}"
DEV_KUBE_DIR="${DEV_KUBE_DIR:-/var/lib/dev/kube}"
DEV_K3S_STATE_DIR=/var/lib/rancher
DEV_K3S_SOURCE_CONFIG=/etc/rancher/k3s/k3s.yaml
DEV_K3S_LOG=/var/log/k3s.log
DEV_K3S_BRIDGE=br-k3s
DEV_K3S_PATTERN='^/usr/local/bin/k3s server'

k3s_usage() {
    cat <<'EOF'
Bring a single-node k3s cluster up or down in this container.

  dev k3s up | down | status

The container needs the full capability set, which k3s does not come up
without: run it with --privileged, or with privileged: true under the Helm
chart.

Cluster state lives on a sparse ext4 image at ~/.dev-k3s.img, loop-mounted at
/var/lib/rancher, so it survives the container. Set DEV_K3S_DISK to size that
image and DEV_K3S_NODE_IP to move the node address; the defaults are 8G and
10.99.0.1.

kubectl needs no setup. KUBECONFIG names your own ~/.kube/config and the
cluster's, and the cluster context is called k3s. Select it with
"kubectl config use-context k3s". Those files live under /var/lib/dev/kube,
because kubectl cannot take its lock file on a virtiofs home; ~/.kube/config
is the real file, symlinked in, so what you write there persists.

The server runs as background work, so it and its workloads lose the contest
for CPU and memory ahead of your session. The log is /var/log/k3s.log.
EOF
}

k3s_verbs() { printf '%s\n' up down status; }

k3s_running() { pgrep -f "$DEV_K3S_PATTERN" >/dev/null 2>&1; }

k3s_brief() { k3s_running && echo "node $DEV_K3S_NODE_IP"; return 0; }

k3s_user() { printf '%s\n' "${SUDO_USER:-$(id -un)}"; }

k3s_home() {
    local home
    home="$(getent passwd "$(k3s_user)" | cut -d: -f6)"
    printf '%s\n' "${home:-$HOME}"
}

k3s_image() { printf '%s/.dev-k3s.img\n' "$(k3s_home)"; }

k3s_loop() { losetup -j "$(k3s_image)" 2>/dev/null | head -1 | cut -d: -f1; }

k3s_in_userns() {
    local first count
    read -r first _ count < /proc/self/uid_map 2>/dev/null || return 1
    [ "$first" = 0 ] && [ "$count" = 4294967295 ] && return 1
    return 0
}

k3s_as_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    exec sudo env \
        DEV_K3S_DISK="$DEV_K3S_DISK" \
        DEV_K3S_NODE_IP="$DEV_K3S_NODE_IP" \
        DEV_KUBE_DIR="$DEV_KUBE_DIR" \
        /usr/local/bin/dev k3s "$1"
}

k3s_mount_state() {
    local image loop
    image="$(k3s_image)"
    findmnt -rno TARGET "$DEV_K3S_STATE_DIR" >/dev/null 2>&1 && return 0
    if [ ! -f "$image" ]; then
        echo "k3s: creating a $DEV_K3S_DISK cluster disk at $image (sparse)"
        truncate -s "$DEV_K3S_DISK" "$image"
        chown "$(k3s_user)" "$image"
        mkfs.ext4 -q -F "$image"
    fi
    mkdir -p "$DEV_K3S_STATE_DIR"
    loop="$(k3s_loop)"
    [ -n "$loop" ] || loop="$(losetup --find --show "$image")"
    mount "$loop" "$DEV_K3S_STATE_DIR"
}

k3s_prepare_kernel() {
    mount -o remount,rw /proc/sys 2>/dev/null || true
    sysctl -qw net.ipv4.ip_forward=1
    sysctl -qw net.ipv6.conf.all.forwarding=1 2>/dev/null || true
}

k3s_prepare_cgroups() {
    local type procs pid available wanted enable=""
    type="$(cat /sys/fs/cgroup/cgroup.type 2>/dev/null || echo domain)"
    if [ "$type" = "domain threaded" ]; then
        echo "error: the root cgroup is 'domain threaded', which the kernel" >&2
        echo "cannot convert back to a resource domain. Recreate the container" >&2
        echo "to clear it — the cluster disk is preserved." >&2
        return 1
    fi
    mkdir -p /sys/fs/cgroup/init
    procs="$(cat /sys/fs/cgroup/cgroup.procs)"
    for pid in $procs; do
        printf '%s\n' "$pid" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    available=" $(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null) "
    for wanted in cpuset cpu io memory hugetlb pids; do
        case "$available" in *" $wanted "*) enable="$enable +$wanted" ;; esac
    done
    for wanted in cpuset cpu memory pids; do
        case "$enable" in
            *"+$wanted"*) ;;
            *)
                echo "error: the kernel offers no $wanted controller here, and" >&2
                echo "kubelet does not run without it. Available:${available%% }" >&2
                return 1 ;;
        esac
    done
    if ! printf '%s\n' "${enable# }" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null; then
        echo "error: cannot delegate cgroup controllers to kubelet. The" >&2
        echo "container is most likely missing CAP_SYS_ADMIN — run it with" >&2
        echo "--privileged, or with privileged: true under the Helm chart." >&2
        return 1
    fi
}

k3s_prepare_network() {
    ip link show "$DEV_K3S_BRIDGE" >/dev/null 2>&1 && return 0
    ip link add "$DEV_K3S_BRIDGE" type bridge
    ip addr add "$DEV_K3S_NODE_IP/24" dev "$DEV_K3S_BRIDGE"
    ip link set "$DEV_K3S_BRIDGE" up
}

k3s_write_kubeconfig() {
    local user home config
    user="$(k3s_user)"
    home="$(k3s_home)"
    config="$home/.kube/config"
    install -d -o "$user" -g "$user" "$DEV_KUBE_DIR" "$home/.kube"
    if [ ! -e "$config" ] && [ ! -L "$config" ]; then
        printf 'apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\nusers: []\npreferences: {}\n' \
            > "$config"
        chmod 600 "$config"
        chown "$user:$user" "$config"
    fi
    ln -sfn "$config" "$DEV_KUBE_DIR/config"
    [ -s "$DEV_K3S_SOURCE_CONFIG" ] || return 0
    sed 's/: default$/: k3s/' "$DEV_K3S_SOURCE_CONFIG" > "$DEV_KUBE_DIR/k3s.yaml.tmp"
    chmod 600 "$DEV_KUBE_DIR/k3s.yaml.tmp"
    chown "$user:$user" "$DEV_KUBE_DIR/k3s.yaml.tmp"
    mv "$DEV_KUBE_DIR/k3s.yaml.tmp" "$DEV_KUBE_DIR/k3s.yaml"
}

k3s_publish_kubeconfig() {
    (
        for _ in $(seq 1 120); do
            [ -s "$DEV_K3S_SOURCE_CONFIG" ] && break
            sleep 1
        done
        k3s_write_kubeconfig
    ) >/dev/null 2>&1 &
}

k3s_deprioritize_server() {
    (
        local pid adj
        for _ in $(seq 1 180); do
            pid="$(pgrep -f "$DEV_K3S_PATTERN" | head -1)"
            if [ -n "$pid" ]; then
                adj="$(cat "/proc/$pid/oom_score_adj" 2>/dev/null || echo 0)"
                [ "$adj" -lt 0 ] && break
            fi
            sleep 1
        done
        [ -n "${pid:-}" ] && echo 1000 > "/proc/$pid/oom_score_adj"
    ) >/dev/null 2>&1 &
}

k3s_up() {
    k3s_as_root up
    if k3s_running; then echo "k3s is already running"; return 0; fi
    k3s_prepare_kernel
    k3s_prepare_cgroups
    k3s_prepare_network
    k3s_mount_state
    [ -s /etc/machine-id ] || tr -d '-' < /proc/sys/kernel/random/uuid > /etc/machine-id
    k3s_write_kubeconfig
    k3s_publish_kubeconfig
    local extra=()
    if k3s_in_userns; then
        extra+=(--kubelet-arg=feature-gates=KubeletInUserNamespace=true)
    fi
    setsid nohup /usr/local/bin/dev bg /usr/local/bin/k3s server \
        --write-kubeconfig-mode 644 \
        --node-ip "$DEV_K3S_NODE_IP" \
        --flannel-iface "$DEV_K3S_BRIDGE" \
        "${extra[@]}" \
        >> "$DEV_K3S_LOG" 2>&1 < /dev/null &
    k3s_deprioritize_server
    echo "k3s: starting in the background; watch it with: dev k3s status"
}

k3s_down() {
    k3s_as_root down
    local image loop waited=0
    pkill -f "$DEV_K3S_PATTERN" 2>/dev/null || true
    pkill -f 'containerd-shim' 2>/dev/null || true
    while k3s_running && [ "$waited" -lt 20 ]; do sleep 1; waited=$((waited + 1)); done
    awk '{print $2}' /proc/mounts \
        | grep -E '^(/var/lib/rancher/|/var/lib/kubelet|/run/k3s|/run/netns)' \
        | sort -r \
        | while read -r m; do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true; done || true
    image="$(k3s_image)"
    loop="$(k3s_loop)"
    if [ -n "$loop" ] && [ "$(findmnt -rno SOURCE "$DEV_K3S_STATE_DIR" 2>/dev/null)" = "$loop" ]; then
        umount "$DEV_K3S_STATE_DIR" 2>/dev/null \
            || umount -l "$DEV_K3S_STATE_DIR" 2>/dev/null || true
    fi
    waited=0
    while [ -n "$(k3s_loop)" ] && [ "$waited" -lt 30 ]; do
        losetup -d "$(k3s_loop)" 2>/dev/null || true
        [ -n "$(k3s_loop)" ] || break
        sleep 1
        waited=$((waited + 1))
    done
    if [ -f "$image" ]; then
        echo "k3s: stopped; cluster state kept in $image"
    else
        echo "k3s: stopped; cluster state kept in $DEV_K3S_STATE_DIR"
    fi
}

k3s_status() {
    k3s_as_root status
    if ! k3s_running; then
        echo "k3s: not running"
        [ -s "$DEV_K3S_LOG" ] && tail -n 5 "$DEV_K3S_LOG" | sed 's/^/log: /'
        return 1
    fi
    echo "k3s: running on $DEV_K3S_NODE_IP"
    findmnt -rno SIZE,USED,TARGET "$DEV_K3S_STATE_DIR" 2>/dev/null | sed 's/^/disk: /' || true
    if ! /usr/local/bin/k3s kubectl get nodes 2>/dev/null; then
        echo "the API server is not ready yet — see $DEV_K3S_LOG"
        return 0
    fi
    /usr/local/bin/k3s kubectl get pods -A 2>/dev/null || true
}
