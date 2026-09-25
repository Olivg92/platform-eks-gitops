# Terraform bootstrap

Creates the S3 bucket that holds the Terraform state of every other stack.

This is the chicken-and-egg stack: it cannot store its own state remotely, because it is what
creates the remote backend. It therefore runs with **local state**, once, and is left alone.
Its state file stays on the operator's machine and is not committed.

## What it creates

| Resource | Why |
|---|---|
| S3 bucket | Holds `terraform.tfstate` for the other stacks |
| Versioning | A corrupted or truncated state can be restored from a previous version |
| Server-side encryption (SSE-S3) | State files contain resource identifiers and sometimes secrets |
| Public access block | A public state bucket is a full map of the infrastructure |
| Lifecycle rule | Old versions expire after 30 days so the bucket does not grow forever |
| Bucket policy | Denies any request that is not over TLS |

State locking uses the **native S3 lock file**, available since Terraform 1.10. The DynamoDB table
every older guide asks for is no longer needed, which also removes a resource to pay for and clean up.

## Cost

A few cents per month at most: state files are kilobytes, and requests are counted in dozens.
This is the only stack that is not destroyed at the end of a session.

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in the account id and a unique bucket name
AWS_PROFILE=perso terraform init
AWS_PROFILE=perso terraform apply
```

The bucket name it prints goes into `terraform/envs/demo/backend.hcl`, which is also not committed.
