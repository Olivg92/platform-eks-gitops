# Terraform

AWS infrastructure for the demo environment.

| Directory | Purpose |
|---|---|
| [`bootstrap/`](bootstrap/) | S3 bucket holding the remote state (applied once, local state) |
| [`modules/`](modules/) | Reusable modules: `vpc`, `eks`, `iam` |
| [`envs/demo/`](envs/demo/) | The demo environment, composed from the modules |
