# Application Database Secret Contract

## Purpose

Define the application PostgreSQL credential format shared by the Task 4 bootstrap Job, AWS Secrets Manager, Secrets Store CSI driver, and Go API.

## Secret ownership

- Terraform creates the application secret without a secret value.
- The controlled database bootstrap Job creates a restricted PostgreSQL application user.
- The bootstrap Job writes the application credentials to AWS Secrets Manager.
- The application runtime has read-only access to the application secret.
- The application runtime must never access RDS master credentials.

## Secret JSON format

```json
{
  "username": "app_user",
  "password": "<generated-secure-password>"
}
```

The username is a proposed application identity and must match the SQL user created during bootstrap.

The password is generated securely during bootstrap. No real credentials belong in this document or the Git repository.

## Runtime contract

- `DB_USER` must match the secret's `username` field.
- `DB_PASSWORD_FILE` points to `/mnt/secrets-store/db-password`.
- The Secrets Store CSI configuration extracts only the JSON `password` field into that file.
- `DB_SSLMODE` must equal `verify-full`.
- `DB_SSLROOTCERT` points to `/etc/ssl/rds/global-bundle.pem`.
- The API must not start successfully with missing credentials or an invalid CA certificate.

## Security requirements

- Never store database passwords in Helm values or ConfigMaps.
- Never expose the RDS master secret to the API runtime.
- Mount secrets only into workloads that require them.
- Restrict database privileges to the application's operational needs.
- Do not deploy the API until bootstrap and secret mounting are implemented and validated.

## Implementation status

- Application database secret contract: defined.
- Terraform application secret resource: implemented.
- AWS Secrets Manager CSI configuration: implemented and locally validated.
- RDS CA certificate ConfigMap and volume mount: implemented and locally validated.
- PostgreSQL application-user bootstrap Job: not yet implemented.
- Live AWS Secrets Manager retrieval and RDS connectivity: not yet validated.
- Production Kubernetes deployment: not yet performed.