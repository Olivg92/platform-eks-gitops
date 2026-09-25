# 0009. Run the nodes in public subnets, without a NAT Gateway

- **Status**: Accepted
- **Date**: 2026-09-25

## Context

Kubernetes nodes need to reach the internet: pull images, call AWS APIs, talk to the control plane.
They must not be reachable from it. The textbook answer is private subnets plus a NAT Gateway.

A NAT Gateway costs $0.045 per hour, per availability zone, plus $0.045 per GB processed. For a
highly available setup that is three of them, around $100 a month, before a single container runs.
On a cluster that exists for an afternoon it is by far the most expensive resource, and the one
most often left behind when a lab is deleted in a hurry.

## Options considered

1. **Private subnets with NAT Gateways**: the production default. Correct, and about $33 a month
   per zone for an environment meant to live three hours.
2. **Private subnets with VPC endpoints**: interface endpoints for ECR, STS, EC2 and others remove
   the need for NAT for AWS traffic, at $0.01 per hour each. Five endpoints across two zones is
   $0.10 an hour, more than the cluster itself, and images from quay.io or ghcr.io still would not
   be reachable.
3. **Public subnets, no NAT**: nodes get a public IP at $0.005 per hour each and route directly
   through the Internet Gateway, which is free. Exposure is then entirely a matter of security groups.

## Decision

Public subnets, no NAT Gateway. The nodes carry a public IP and the security group EKS creates
allows no inbound traffic except from the control plane and the load balancer.

The choices that make this defensible rather than careless:

- IMDSv2 is required, with a hop limit of 1, so instance credentials cannot be read from inside a
  pod, which is the usual next step after a container escape.
- The node role carries only the three policies a node needs. Workload permissions are granted per
  application with EKS Pod Identity, not piled onto the node.
- The default security group of the VPC is emptied, so anything landing in it by accident is isolated.
- Network policies deny traffic between pods that has no reason to exist.

## Consequences

- The environment costs about $0.15 an hour instead of $0.20 or more, and nothing keeps billing
  once `make down` has run: there is no NAT Gateway to forget.
- Security rests entirely on the security groups. A single over-permissive rule exposes a node
  directly to the internet, where the same mistake behind a NAT would be harmless.
- **This is not what I would run in production.** There, nodes belong in private subnets, with NAT
  Gateways or VPC endpoints depending on the traffic profile, and the API server endpoint would be
  private with access through a bastion or a VPN.
