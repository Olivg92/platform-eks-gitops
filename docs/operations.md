# Operating the platform

Day-to-day details that the [README](../README.md) leaves out: which cluster a command talks to,
what usually goes wrong locally, and how to test a branch before merging it. Alerts have their own
[runbooks](runbooks/).

## Which cluster am I talking to?

Each environment has a kubeconfig file of its own, and every `make` target uses one explicitly:
`~/.kube/platform-eks-gitops-local` for k3d, `~/.kube/platform-eks-gitops-aws` for EKS. The default
`~/.kube/config` is never read and never written, so the targets cannot act on another cluster the
machine happens to know about, and creating the local cluster no longer switches the current context
of whoever was working on something else.

```bash
make context              # the local cluster
make context ENV=aws      # the EKS cluster, or "not running"
```

To use `kubectl` by hand, point it at the same file:

```bash
export KUBECONFIG=~/.kube/platform-eks-gitops-local
```

The scripts shared by both environments refuse to run without `KUBECONFIG` rather than fall back on
the default one.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Pods stuck in `ImagePullBackOff`, events showing `lookup <registry>: Try again` | k3d nodes keep the DNS servers they were created with. Moving between networks, or connecting to a VPN, leaves them pointing at a resolver they can no longer reach. | `make local-restart` |
| `make local-up` fails on the Argo CD install with `context deadline exceeded` | Same cause: the pods never become ready because their images cannot be pulled. | `make local-restart`, then `make local-up` again |
| Grafana rejects the password from `make grafana-password`, usually after a machine reboot | Vault runs in dev mode and keeps nothing on disk, so it regenerates the password on restart. Grafana only reads it when it starts, so it still holds the previous one. | `make grafana-reload` |
| An application stays `OutOfSync` while everything is healthy | Expected while testing a branch: the root application is paused on purpose (see below). | `make local-bootstrap` once the branch is merged |

## Testing a branch

Applications committed here track `main`, which is the source of truth. To try a branch before
merging it, push the branch and run `make local-up REVISION=my-branch`: the root Application
follows that branch and [`scripts/dev-follow-revision.sh`](../scripts/dev-follow-revision.sh)
repoints the others at it.

## Tearing down AWS

`make down` stops Argo CD, deletes the Kubernetes objects that own AWS resources, destroys the
stack, then lists anything still billing and exits non-zero if something is. The reasons for that
order, and the same sequence by hand, are in [the runbooks](runbooks/README.md#tearing-down-the-aws-environment).
