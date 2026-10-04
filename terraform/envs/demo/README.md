# Demo environment

Wires the modules together: the network, the EKS cluster with its Spot nodes, and what External
Secrets needs to read from Secrets Manager. `make up` creates it, `make down` destroys it, and
nothing here is meant to outlive a session.

## What it creates

| Module | Resources |
|---|---|
| [`vpc`](../../modules/vpc/) | A VPC, two public subnets, an internet gateway and their route table. No NAT Gateway ([ADR 0009](../../../docs/adr/0009-public-subnets-without-a-nat-gateway.md)) |
| [`eks`](../../modules/eks/) | The cluster, a managed node group of Spot instances behind a launch template, their IAM roles, and four add-ons: VPC CNI with network policies, CoreDNS, kube-proxy, Pod Identity agent |
| [`workload-identity`](../../modules/workload-identity/) | Two secrets in Secrets Manager, and the Pod Identity association that lets External Secrets read those two and nothing else ([ADR 0010](../../../docs/adr/0010-pod-identity-for-workload-credentials.md)) |

The load balancer in front of the gateway is not here: Kubernetes requests it once Envoy Gateway
starts, which is why `make down` deletes it before destroying this stack.

## Files to create once

`make aws-setup` writes both from the account of the profile, and checks them on every later run.
Neither is committed: both hold values that belong to one account.

| File | What it holds | By hand, copy |
|---|---|---|
| `backend.hcl` | The state bucket, found in the account or created by [`terraform/bootstrap`](../../bootstrap/) | `backend.hcl.example` |
| `terraform.tfvars` | The AWS account id, since Terraform refuses to act on any other account; the region, and two zones EKS accepts | `terraform.tfvars.example` |

## Variables

| Variable | Default | Notes |
|---|---|---|
| `account_id` | none | A machine with several AWS profiles is one typo away from the wrong account: this makes that a hard error |
| `api_public_access_cidrs` | none | Who may reach the Kubernetes API. `make up` fills it with the address of the machine running it, and Terraform refuses `0.0.0.0/0`. Not meant to be set by hand |
| `region` | `eu-north-1` | See below to change it |
| `availability_zones` | `eu-north-1a`, `eu-north-1b` | One public subnet in each |
| `name` | `platform-demo` | Prefix of every resource |
| `kubernetes_version` | `1.36` | The same version as the local k3d cluster |
| `node_count` | `2` | Spot `t3.medium` instances |

## Another region

Three settings name the region, and they have to agree:

- `region` and `availability_zones` in `terraform.tfvars`;
- `AWS_REGION` in `local.mk` at the root of the repository, which `make up` and `make down` use
  for the kubeconfig and for the final check that nothing is left.

`make aws-setup` writes the three from the same choice, and stops when they disagree. The state
bucket can stay where it is: `backend.hcl` names the region of the bucket, not the region of this
environment.
