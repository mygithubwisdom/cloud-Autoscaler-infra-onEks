# Existing state bucket bootstrap

This root creates the protected state bucket. It has already been applied by the
project owner. Keep its existing local `terraform.tfstate` securely on the owner's
machine; it is intentionally not in Git. Moving the directory does not move AWS
resources. Do not apply from a new clone with empty state to recreate the bucket.

The resources enable versioning, AES256 encryption, block public access, enforce
HTTPS and use prevent_destroy. Retain this provider lock file. No EKS, node, CAS,
application or GitHub OIDC resources belong here.

See `../README.md` before using the generated backend output: its historical key
currently differs from `../infra/backend.prod.hcl`. Neither location should be
changed or migrated until the initialized backend location is confirmed.
