# dev-container Helm chart

Runs `ghcr.io/brhelwig/dev-container` as a single persistent pod on Docker
Desktop or GKE, amd64 or arm64, with a home directory that survives pod
restarts. It's a `StatefulSet`, so the pod gets a stable name and DNS entry
(`<release>-dev-container-0`) instead of a new random name every time it's
recreated.

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
kubectl exec -it statefulset/dev-dev-container -- zsh
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

Keyless SSH login:

```sh
helm install dev chart/dev-container \
  --set sshAuthorizedKeys[0]="ssh-ed25519 AAAA... me@laptop"
```

Tailscale — `tailscaled` always runs; by default you connect it the normal
way, a one-time interactive login via `exec`:

```sh
kubectl exec -it statefulset/dev-dev-container -- sudo tailscale up
```

That prints a login URL to open in a browser. For a fully unattended
bootstrap instead, create a Secret holding an auth key yourself first (the
chart never takes the key as a plain value):

```sh
kubectl create secret generic ts-authkey --from-literal=authkey=tskey-...
helm install dev chart/dev-container --set tailscale.authKeySecretName=ts-authkey
```

GKE Workload Identity, once the cluster/nodepool has it enabled and the GCP
IAM binding is in place (`gcloud iam service-accounts add-iam-policy-binding
<gsa> --role roles/iam.workloadIdentityUser --member "serviceAccount:<project>.svc.id.goog[<namespace>/dev-dev-container]"`):

```sh
helm install dev chart/dev-container \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=my-gsa@my-project.iam.gserviceaccount.com
```

## Values

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/brhelwig/dev-container` | Image to run |
| `image.tag` | `latest` | Image tag |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | For a private registry |
| `command` | `[]` | Leave empty — the image's own `ENTRYPOINT` starts sshd/Tailscale/the VS Code tunnel/zellij; setting this would replace it entirely |
| `args` | `["sleep", "infinity"]` | Overrides only the image's `CMD` (an interactive shell with nothing to run without a tty), keeping the pod alive |
| `sshAuthorizedKeys` | `[]` | Public keys to seed into `~/.ssh/authorized_keys` for keyless SSH login |
| `tailscale.authKeySecretName` | `""` | Secret holding a Tailscale auth key, for unattended `tailscale up`; leave empty to do it manually via `exec` instead |
| `tailscale.authKeySecretKey` | `authkey` | Key within that Secret |
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
| `serviceAccount.create` | `true` | |
| `serviceAccount.name` | `""` | Defaults to the chart's fullname |
| `serviceAccount.annotations` | `{}` | Set `iam.gke.io/gcp-service-account` here for GKE Workload Identity |

Only `/home/dev` is persisted. k3s and podman state live in the pod's own
writable layer and are lost when the pod is recreated — the container is
disposable, the home directory isn't.

The image's `entrypoint.sh` seeds `/home/dev` from `/etc/skel` (oh-my-zsh,
`.zshrc`, the brew `shellenv` line) the first time the volume is used,
since a freshly provisioned PVC — or an `emptyDir`, if
`persistence.enabled: false` — starts empty regardless of what the image
itself has baked in. The same script starts `sshd`, `tailscaled`, the VS
Code tunnel (if already signed in), and a persistent `zellij` session named
`dev` — join it with `kubectl exec -it statefulset/<release> -- zellij attach dev`.
