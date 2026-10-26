# Existing state bucket bootstrap

This root creates the protected state bucket. It has already been applied by the
project owner. Keep its existing local `terraform.tfstate` securely on the owner's
machine; it is intentionally not in Git. Moving the directory does not move AWS
resources. Do not apply from a new clone with empty state to recreate the bucket.

The resources enable versioning, AES256 encryption, block public access, enforce
HTTPS and use prevent_destroy. Retain this provider lock file. No EKS, node, CAS,
application or GitHub OIDC resources belong here.

The backend output points to `../infra/backend.prod.hcl`. Its state key matches
the owner's confirmed initialized location, `task1-assessment/prod/terraform.tfstate`.
Do not change this key or migrate state when moving directories. See `../README.md`.
