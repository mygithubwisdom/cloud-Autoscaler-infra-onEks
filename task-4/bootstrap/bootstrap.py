#!/usr/bin/env python3
"""Bootstrap restricted PostgreSQL application credentials."""

import json
import logging
import os
import secrets

import boto3
import psycopg
from psycopg import sql


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

logger = logging.getLogger("database-bootstrap")


def required_env(name):
    """Return a required environment variable."""
    value = os.environ.get(name)

    if not value:
        raise ValueError(f"Missing required environment variable: {name}")

    return value

def get_secret_json(client, secret_arn):
    """Retrieve and validate a JSON credential secret."""
    response = client.get_secret_value(SecretId=secret_arn)

    secret_string = response.get("SecretString")
    if not secret_string:
        raise ValueError("SecretString is missing")

    secret_data = json.loads(secret_string)

    if not isinstance(secret_data, dict):
        raise ValueError("Secret must contain a JSON object")

    username = secret_data.get("username")
    password = secret_data.get("password")

    if not isinstance(username, str) or not username:
        raise ValueError("Secret username is missing or invalid")

    if not isinstance(password, str) or not password:
        raise ValueError("Secret password is missing or invalid")

    return secret_data

def get_existing_application_credentials(client, secret_arn):
    """Read application credentials, allowing an uninitialized secret."""
    from botocore.exceptions import ClientError

    try:
        return get_secret_json(client, secret_arn)

    except ClientError as error:
        error_code = error.response.get("Error", {}).get("Code")

        if error_code == "ResourceNotFoundException":
            # Verify that the secret resource itself exists.
            # A missing version is different from a missing secret.
            metadata = client.describe_secret(SecretId=secret_arn)

            if metadata.get("DeletedDate"):
                raise ValueError(
                    "Application secret is scheduled for deletion"
                ) from error

            versions = metadata.get("VersionIdsToStages", {})

            if not versions:
                logger.info("Application secret has no versions")
                return None

            raise ValueError(
                "Application secret exists but its current version "
                "could not be retrieved"
            ) from error

        raise


def generate_secure_password():
    """Generate a cryptographically secure database password."""
    return secrets.token_urlsafe(48)

def prepare_application_credentials(existing_credentials):
    """Reuse existing credentials or prepare new application credentials."""
    if existing_credentials is not None:
        if existing_credentials.get("username") != "app_user":
            raise ValueError("Unexpected application credentials username")

        password = existing_credentials.get("password")
        if not isinstance(password, str) or not password:
            raise ValueError("Application password is missing or invalid")

        logger.info("Existing application credentials will be reused")
        return existing_credentials, False

    logger.info("Preparing new application credentials")
    return {
        "username": "app_user",
        "password": generate_secure_password(),
    }, True

def publish_application_credentials(
    client, secret_arn, credentials, request_token=None
):
    """Publish credentials and reconcile uncertain AWS responses."""
    import uuid
    from botocore.exceptions import (
        BotoCoreError,
        ClientError,
    )

    if credentials.get("username") != "app_user":
        raise ValueError("Unexpected application credentials username")

    password = credentials.get("password")
    if not isinstance(password, str) or not password:
        raise ValueError("Application password is missing or invalid")

    if request_token is None:
        request_token = str(uuid.uuid4())

    try:
        response = client.put_secret_value(
            SecretId=secret_arn,
            SecretString=json.dumps(credentials),
            ClientRequestToken=request_token,
        )

    except (BotoCoreError, ClientError):
        logger.warning(
            "Secret publication returned an error; "
            "checking the expected version"
        )

        try:
            stored = client.get_secret_value(
                SecretId=secret_arn,
                VersionId=request_token,
            )
        except (BotoCoreError, ClientError):
            logger.error(
                "Unable to confirm secret publication; "
                "bootstrap will stop safely"
            )
            raise RuntimeError(
                "Secret publication outcome is uncertain"
            ) from None

        try:
            stored_credentials = json.loads(
                stored["SecretString"]
            )
        except (KeyError, TypeError, ValueError):
            raise RuntimeError(
                "Published secret version is unreadable"
            ) from None

        if stored_credentials != credentials:
            raise RuntimeError(
                "Published secret version does not match "
                "expected credentials"
            )

        logger.info(
            "Secret publication recovered using expected version"
        )
        return request_token

    logger.info(
        "Application credentials published to Secrets Manager"
    )
    return response["VersionId"]


def postgres_role_exists(connection, role_name):
    """Check whether a PostgreSQL role already exists."""
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = %s)",
            (role_name,),
        )
        result = cursor.fetchone()
        return bool(result[0])

def create_application_role(connection, role_name, password):
    """Create a restricted PostgreSQL login role if absent."""
    if role_name != "app_user":
        raise ValueError("Unexpected application role name")

    if postgres_role_exists(connection, role_name):
        logger.info("Application role already exists")
        return False

    with connection.cursor() as cursor:
        cursor.execute(
            sql.SQL(
                "CREATE ROLE {} WITH LOGIN PASSWORD {} "
                "NOSUPERUSER NOCREATEDB NOCREATEROLE "
                "NOREPLICATION NOINHERIT"
            ).format(
                sql.Identifier(role_name),
                sql.Literal(password),
            )
        )

    logger.info("Restricted application role created")
    return True

def acquire_bootstrap_lock(connection):
    """Serialize PostgreSQL bootstrap operations."""
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT pg_advisory_xact_lock(%s)",
            (460118,),
        )

    logger.info("PostgreSQL bootstrap transaction lock acquired")

def grant_application_permissions(connection, database_name, role_name):
    """Grant minimum database access to the application role."""
    if role_name != "app_user":
        raise ValueError("Unexpected application role name")

    with connection.cursor() as cursor:
        cursor.execute(
            sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(
                sql.Identifier(database_name),
                sql.Identifier(role_name),
            )
        )

        cursor.execute(
            sql.SQL("GRANT USAGE ON SCHEMA public TO {}").format(
                sql.Identifier(role_name),
            )
        )

    logger.info("Minimum application database permissions granted")

def connect_to_postgres(host, database, credentials, ca_bundle):
    """Connect to PostgreSQL using verified TLS."""
    logger.info("Connecting to PostgreSQL using verified TLS")

    connection = psycopg.connect(
        host=host,
        port=5432,
        dbname=database,
        user=credentials["username"],
        password=credentials["password"],
        sslmode="verify-full",
        sslrootcert=ca_bundle,
        connect_timeout=10,
    )

    logger.info("PostgreSQL TLS connection established")
    return connection

def determine_bootstrap_action(existing_credentials, role_exists):
    """Determine the required database bootstrap operation."""

    if existing_credentials is not None:
        if existing_credentials.get("username") != "app_user":
            raise ValueError("Unexpected application credentials username")

        password = existing_credentials.get("password")
        if not isinstance(password, str) or not password:
            raise ValueError("Application password is missing or invalid")

        if role_exists:
            logger.info("Existing database role and secret found")
            return "reuse"

        logger.warning(
            "Application secret exists but database role is missing"
        )
        return "recover_role"

    if role_exists:
        raise RuntimeError(
            "Application database role exists without a valid secret; "
            "manual recovery is required"
        )

    logger.info("Initial application database setup required")
    return "initialize"

def main():
    logger.info("Starting PostgreSQL application database bootstrap")

    aws_region = required_env("AWS_REGION")
    rds_host = required_env("RDS_HOST")
    rds_database = required_env("RDS_DATABASE")
    master_secret_arn = required_env("RDS_MASTER_SECRET_ARN")
    app_db_secret_arn = required_env("APP_DB_SECRET_ARN")
    ca_bundle = required_env("RDS_CA_BUNDLE")

    secrets_client = boto3.client(
        "secretsmanager",
        region_name=aws_region,
    )

    master_credentials = get_secret_json(
        secrets_client,
        master_secret_arn,
    )

    with connect_to_postgres(
        host=rds_host,
        database=rds_database,
        credentials=master_credentials,
        ca_bundle=ca_bundle,
    ) as connection:

        acquire_bootstrap_lock(connection)

        existing_credentials = get_existing_application_credentials(
            secrets_client,
            app_db_secret_arn,
        )

        role_exists = postgres_role_exists(connection, "app_user")

        action = determine_bootstrap_action(
            existing_credentials,
            role_exists,
        )

        logger.info("Bootstrap action: %s", action)

        if action == "initialize":
            credentials, should_publish = prepare_application_credentials(
                existing_credentials
            )

            create_application_role(
                connection,
                "app_user",
                credentials["password"],
            )

            grant_application_permissions(
                connection,
                rds_database,
                "app_user",
            )

            if should_publish:
                publish_application_credentials(
                    secrets_client,
                    app_db_secret_arn,
                    credentials,
                )

        elif action == "recover_role":
            credentials = existing_credentials

            create_application_role(
                connection,
                "app_user",
                credentials["password"],
            )

            grant_application_permissions(
                connection,
                rds_database,
                "app_user",
            )

        elif action == "reuse":
            credentials = existing_credentials

    # The database transaction has committed here.
    verify_application_credentials(
        host=rds_host,
        database=rds_database,
        credentials=credentials,
        ca_bundle=ca_bundle,
    )

    logger.info("PostgreSQL application bootstrap completed")


def verify_application_credentials(
    host, database, credentials, ca_bundle
):
    """Verify that the application credentials can authenticate."""

    if credentials.get("username") != "app_user":
        raise ValueError("Unexpected application credentials username")

    with connect_to_postgres(
        host=host,
        database=database,
        credentials=credentials,
        ca_bundle=ca_bundle,
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT current_user")
            authenticated_user = cursor.fetchone()[0]

            if authenticated_user != "app_user":
                raise RuntimeError(
                    "Unexpected authenticated PostgreSQL user"
                )

    logger.info("Application database credentials verified")
    return True

if __name__ == "__main__":
    main()
