# dev-container Helm chart

Runs `ghcr.io/brhelwig/dev-container` as a single persistent pod on Docker
Desktop or GKE, amd64 or arm64, with a home directory that survives pod
restarts.

## Requirements

**The pod runs privileged.** podman and k3s need root-level kernel access
(overlayfs, cgroups, network namespaces), and there's no lighter-weight way
to give them that inside a container. This means:

- **GKE Standard, not Autopilot** — Autopilot rejects privileged pods outright.
- The target namespace must not enforce a "restricted" or "baseline" Pod
  Security Standard.

## Install

```sh
helm install dev chart/dev-container
kubectl exec -it deploy/dev-dev-container -- zsh
```

## Examples

Docker Desktop, defaults are already fine for its `hostpath` StorageClass:

```sh
helm install dev chart/dev-container
```

GKE, pinned to a nodepool and its regional persistent-disk storage class:

```sh
helm install dev chart/dev-container \
  --set persistence.storageClassName=standard-rwo \
  --set nodeSelector."cloud\.google\.com/gke-nodepool"=dev-pool
```

Pin to one architecture on a mixed-arch nodepool:

```sh
helm install dev chart/dev-container --set arch=arm64
```

Bind to a PVC you already created instead of letting the chart make one:

```sh
helm install dev chart/dev-container --set persistence.existingClaim=my-home-pvc
```

## Values

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/brhelwig/dev-container` | Image to run |
| `image.tag` | `latest` | Image tag |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | For a private registry |
| `command`, `args` | `sleep`, `["infinity"]` | Keeps the pod up; the image's own `CMD` is an interactive shell with nothing to run without a tty |
| `arch` | `""` | `amd64` or `arm64` to pin scheduling via `kubernetes.io/arch`; empty lets either run |
| `nodeSelector` | `{}` | Arbitrary node selection, e.g. a GKE nodepool label |
| `affinity` | `{}` | |
| `tolerations` | `[]` | |
| `resources.requests.cpu` | `2` | |
| `resources.requests.memory` | `4Gi` | |
| `resources.limits.cpu` | `4` | |
| `resources.limits.memory` | `8Gi` | |
| `persistence.enabled` | `true` | Set `false` for an ephemeral `emptyDir` home instead |
| `persistence.size` | `20Gi` | |
| `persistence.storageClassName` | `""` | Empty uses the cluster's default StorageClass |
| `persistence.accessModes` | `["ReadWriteOnce"]` | |
| `persistence.existingClaim` | `""` | Bind to a PVC you already created instead of the chart's own |
| `securityContext.privileged` | `true` | Required for k3s/podman — see Requirements above |
| `podSecurityContext.fsGroup` | `1000` | Matches the image's `dev` user so the PVC is writable without a manual `chown` |

Only `/home/dev` is persisted. k3s and podman state live in the pod's own
writable layer and are lost when the pod is recreated — the container is
disposable, the home directory isn't.
