# dev-container

A Debian-based dev image with a broad toolchain baked in: build-essential,
git/git-lfs, podman, k3s, the VS Code CLI, Homebrew (ansible, awscli,
azure-cli, gh, go, kubectl, terraform, node, and more — see `Dockerfile` for
the full list), and zsh with oh-my-zsh.

```sh
docker pull ghcr.io/brhelwig/dev-container:latest-amd64
docker run -it ghcr.io/brhelwig/dev-container:latest-amd64
```

Built for `linux/amd64` and `linux/arm64` on every push to `main`, weekly,
and on manual dispatch. Each platform is published under its own tag
(`:latest-amd64`, `:latest-arm64`) rather than a combined multi-arch
manifest — pull the tag matching your host's architecture. Most of what it
installs (Homebrew formulae, k3s, the VS Code CLI) tracks an upstream
"latest" channel, so these tags drift over time — there is no pinned or
dated tag.
## The `dev` command

The entrypoint starts an SSH server, tailscale, the podman socket, a VS Code
tunnel and a background zellij session named after the hostname. `dev` reports
on those and drives them.

```
dev                          a menu of the services and what they are doing
dev status                   one line for each service
dev ssh     up|down|status   the SSH server
dev code    login|up|down|status
                             the VS Code tunnel
dev ts      up|down|status   tailscale
dev podman  up|down|status   the podman socket that DOCKER_HOST names
dev k3s     up|down|status   the single-node Kubernetes cluster
dev bg <command>             run a command as background work
dev help                     the full page
```

`up` on something already running says so and stops. Add `--help` to any
service for what it does and where its log is.

Two things the entrypoint does not start. `dev code login` signs in to the
tunnel service the first time; every launch after that starts the tunnel on its
own. `dev k3s up` brings up a single-node cluster, which needs the full
capability set — run the container with `--privileged`, or with
`privileged: true` under the Helm chart.

`dev bg` runs a command niced to 10, in the idle I/O class, and first in line
for the OOM killer. Every command Claude Code spawns is treated that way
already, so a runaway build loses the contest for CPU and memory instead of
your session losing it.

The SSH server refuses to start while `~/.ssh/authorized_keys` is empty, rather
than coming up unreachable. Pass keys in `SSH_AUTHORIZED_KEYS`, or set
`sshAuthorizedKeys` in the Helm chart.
