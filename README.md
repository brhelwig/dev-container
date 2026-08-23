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

Each publish pushes per-platform images by digest before tagging the merged
manifest, so a `Clean up package versions` workflow runs afterward and
removes the untagged versions no current tag points to. Deleting versions
needs more than the `packages: write` the default token already has for
publishing — the package must grant this repository the Admin role under
its Settings → "Manage Actions access", or cleanup runs will fail.

## FreeCAD variant

A second image, `:freecad`, layers a headless CAD toolchain on top of
`:latest` — FreeCAD from its official release AppImage (see
`Dockerfile.freecad`), pinned by release tag and checksum-verified, plus
`potrace` for tracing raster artwork into vector outlines. It rebuilds after
every `:latest` publish and weekly.

```sh
docker pull ghcr.io/brhelwig/dev-container:freecad
docker run --rm ghcr.io/brhelwig/dev-container:freecad freecadcmd --version
```
