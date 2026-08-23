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

## Running one per person

`fullnameOverride` names every object in a release, so one chart can back a
fleet of personal dev containers in a single namespace:

```sh
helm install alice chart/dev-container -n dev --set fullnameOverride=alice-dev
```

That gives a StatefulSet `alice-dev` and a pod `alice-dev-0`. The image's
`entrypoint.sh` runs `tailscale up --hostname="$(hostname)"`, so the pod name
becomes the Tailscale device name and its MagicDNS entry too.

Keep what everyone shares in one values file and the per-person differences —
the name, the service account, the keys — in a second one layered on top:

```sh
helm install alice chart/dev-container -n dev -f common.yaml -f alice.yaml
```

### First login

A freshly provisioned volume has an empty `~/.ssh/authorized_keys`, so SSH is
closed until a key is added. `sshAuthorizedKeys` seeds keys from values; to
keep keys out of a values file altogether, add one after the first install:

```sh
kubectl exec -i -n <namespace> <release>-0 -- \
  sh -c 'cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys' \
  < ~/.ssh/id_ed25519.pub
```

It persists from then on, since `/home/dev` is on the volume. Tailscale also
starts unauthenticated on a new volume, so connect it once:

```sh
kubectl exec -it -n <namespace> <release>-0 -- sudo tailscale up
```

### Sizing to a node

To give the pod a machine to itself, size requests against what the node
actually has free rather than the machine's advertised size. Allocatable is
well below capacity, and system DaemonSets take a further cut:

```sh
kubectl get node <node> \
  -o jsonpath='{.status.allocatable.cpu} {.status.allocatable.memory}{"\n"}'
```

On a 2 vCPU / 8Gi machine that leaves roughly 1.9 CPU and 5.8Gi allocatable,
of which DaemonSets request a few hundred millicores and a few hundred Mi.
Requests near that remainder stop a second pod landing on the node. Limits a
little under allocatable let the container burst without driving the node out
of memory. A limit above allocatable buys nothing, since the node cannot
deliver it.

## Values

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/brhelwig/dev-container` | Image to run |
| `image.tag` | `latest` | Image tag |
| `image.pullPolicy` | `Always` | Re-pulls the image every time the container starts, so restarting the pod picks up a newly pushed `latest` |
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
| `resources.requests.cpu` | `1000m` | |
| `resources.requests.memory` | `4Gi` | |
| `resources.limits.cpu` | `4000m` | |
| `resources.limits.memory` | `8Gi` | |
| `persistence.enabled` | `true` | Set `false` for an ephemeral `emptyDir` home instead |
| `persistence.retainOnDelete` | `true` | Annotates the PVC `helm.sh/resource-policy: keep`, so `helm uninstall` leaves the home directory behind. Set `false` for a throwaway sandbox whose volume should go with the release |
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
