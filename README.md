# dev-container

A Debian-based dev image with a broad toolchain baked in: build-essential,
git/git-lfs, podman, k3s, the VS Code CLI, Homebrew (ansible, awscli,
azure-cli, gh, go, kubectl, terraform, node, and more — see `Dockerfile` for
the full list), and zsh with oh-my-zsh.

```sh
docker pull ghcr.io/brhelwig/dev-container:latest
docker run -it ghcr.io/brhelwig/dev-container:latest
```

Built for `linux/amd64` and `linux/arm64` on every push to `main`, weekly,
and on manual dispatch. Most of what it installs (Homebrew formulae, k3s,
the VS Code CLI) tracks an upstream "latest" channel, so `:latest` drifts
over time — there is no pinned or dated tag.