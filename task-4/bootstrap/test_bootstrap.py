import importlib.util
import json
import pathlib
import os
import unittest
from unittest.mock import Mock, MagicMock, patch

from botocore.exceptions import ClientError

from botocore.exceptions import ClientError

import importlib.util
import json
import pathlib
import unittest
from unittest.mock import Mock, MagicMock, patch

MODULE_PATH = pathlib.Path(__file__).with_name("bootstrap.py")

spec = importlib.util.spec_from_file_location(
    "bootstrap", MODULE_PATH
)
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class TestSecretRetrieval(unittest.TestCase):

    def test_valid_credentials(self):
        client = Mock()
        client.get_secret_value.return_value = {
            "SecretString": json.dumps({
                "username": "dbadmin",
                "password": "example-test-password"
            })
        }

        result = bootstrap.get_secret_json(
            client, "example-secret-arn"
        )

        self.assertEqual(result["username"], "dbadmin")
        self.assertEqual(result["password"], "example-test-password")
        client.get_secret_value.assert_called_once_with(
            SecretId="example-secret-arn"
        )

    def test_missing_password(self):
        client = Mock()
        client.get_secret_value.return_value = {
            "SecretString": json.dumps({
                "username": "dbadmin"
            })
        }

        with self.assertRaises(ValueError):
            bootstrap.get_secret_json(
                client, "example-secret-arn"
            )

    def test_missing_secret_string(self):
        client = Mock()
        client.get_secret_value.return_value = {}

        with self.assertRaises(ValueError):
            bootstrap.get_secret_json(
                client, "example-secret-arn"
            )

    def test_postgres_connection_uses_verified_tls(self):
            from unittest.mock import patch

            credentials = {
                "username": "dbadmin",
                "password": "example-test-password",
            }

            with patch.object(bootstrap.psycopg, "connect") as mock_connect:
                connection = bootstrap.connect_to_postgres(
                    host="db.example.amazonaws.com",
                    database="appdb",
                    credentials=credentials,
                    ca_bundle="/etc/ssl/rds/global-bundle.pem",
                )

            mock_connect.assert_called_once_with(
                host="db.example.amazonaws.com",
                port=5432,
                dbname="appdb",
                user="dbadmin",
                password="example-test-password",
                sslmode="verify-full",
                sslrootcert="/etc/ssl/rds/global-bundle.pem",
                connect_timeout=10,
            )

            self.assertIs(connection, mock_connect.return_value)

    def test_generate_secure_password(self):
        password_one = bootstrap.generate_secure_password()
        password_two = bootstrap.generate_secure_password()

        self.assertIsInstance(password_one, str)
        self.assertGreaterEqual(len(password_one), 48)
        self.assertNotEqual(password_one, password_two)
        self.assertNotIn("\n", password_one)
        self.assertNotIn(" ", password_one)

    def test_postgres_role_exists(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = (True,)

        result = bootstrap.postgres_role_exists(
            connection,
            "app_user",
        )

        self.assertTrue(result)
        cursor.execute.assert_called_once_with(
            "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = %s)",
            ("app_user",),
        )

    def test_postgres_role_does_not_exist(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = (False,)

        result = bootstrap.postgres_role_exists(
            connection,
            "app_user",
        )

        self.assertFalse(result)

    def test_create_application_role_when_absent(self):
        from unittest.mock import patch

        connection = MagicMock()

        with patch.object(
            bootstrap, "postgres_role_exists", return_value=False
        ) as mock_exists:
            created = bootstrap.create_application_role(
                connection,
                "app_user",
                "example-test-password",
            )

        self.assertTrue(created)
        mock_exists.assert_called_once_with(connection, "app_user")

        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.execute.assert_called_once()

        query = cursor.execute.call_args.args[0]

        self.assertEqual(len(cursor.execute.call_args.args), 1)

        sql_statement = query.as_string()

        self.assertIn('CREATE ROLE "app_user"', sql_statement)
        self.assertIn("NOSUPERUSER", sql_statement)
        self.assertIn("NOCREATEDB", sql_statement)
        self.assertIn("NOCREATEROLE", sql_statement)
        self.assertIn("NOINHERIT", sql_statement)

    def test_create_application_role_when_existing(self):
        from unittest.mock import patch

        connection = MagicMock()

        with patch.object(
            bootstrap, "postgres_role_exists", return_value=True
        ):
            created = bootstrap.create_application_role(
                connection,
                "app_user",
                "example-test-password",
            )

        self.assertFalse(created)
        connection.cursor.assert_not_called()

    def test_create_application_role_rejects_unexpected_name(self):
        connection = MagicMock()

        with self.assertRaises(ValueError):
            bootstrap.create_application_role(
                connection,
                "postgres",
                "example-test-password",
            )

        connection.cursor.assert_not_called()

    def test_grant_application_permissions(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value

        bootstrap.grant_application_permissions(
            connection,
            "appdb",
            "app_user",
        )

        self.assertEqual(cursor.execute.call_count, 2)

        first_query = cursor.execute.call_args_list[0].args[0]
        second_query = cursor.execute.call_args_list[1].args[0]

        self.assertEqual(
            first_query.as_string(),
            'GRANT CONNECT ON DATABASE "appdb" TO "app_user"',
        )

        self.assertEqual(
            second_query.as_string(),
            'GRANT USAGE ON SCHEMA public TO "app_user"',
        )

    def test_grant_application_permissions_rejects_unexpected_name(self):
        connection = MagicMock()

        with self.assertRaises(ValueError):
            bootstrap.grant_application_permissions(
                connection,
                "appdb",
                "postgres",
            )

        connection.cursor.assert_not_called()

    def test_existing_application_credentials(self):
        client = Mock()
        client.get_secret_value.return_value = {
            "SecretString": json.dumps({
                "username": "app_user",
                "password": "example-test-password",
            })
        }

        result = bootstrap.get_existing_application_credentials(
            client,
            "example-secret-arn",
        )

        self.assertEqual(result["username"], "app_user")
        self.assertEqual(result["password"], "example-test-password")

    def test_uninitialized_application_secret(self):
        client = Mock()
        client.get_secret_value.return_value = {}

        with self.assertRaisesRegex(
            ValueError,
            "SecretString is missing",
        ):
            bootstrap.get_existing_application_credentials(
                client,
                "example-secret-arn",
            )

    def test_invalid_application_credentials(self):
        client = Mock()
        client.get_secret_value.return_value = {
            "SecretString": json.dumps({
                "username": "app_user",
            })
        }

        with self.assertRaises(ValueError):
            bootstrap.get_existing_application_credentials(
                client,
                "example-secret-arn",
            )

    def test_application_secret_without_versions(self):
        client = Mock()
        client.get_secret_value.side_effect = ClientError(
            {
                "Error": {
                    "Code": "ResourceNotFoundException",
                    "Message": "Secret version not found",
                }
            },
            "GetSecretValue",
        )
        client.describe_secret.return_value = {
            "VersionIdsToStages": {}
        }

        result = bootstrap.get_existing_application_credentials(
            client, "example-secret-arn"
        )

        self.assertIsNone(result)
        client.describe_secret.assert_called_once_with(
            SecretId="example-secret-arn"
        )

    def test_application_secret_resource_missing(self):
        client = Mock()
        client.get_secret_value.side_effect = ClientError(
            {
                "Error": {
                    "Code": "ResourceNotFoundException",
                    "Message": "Secret not found",
                }
            },
            "GetSecretValue",
        )
        client.describe_secret.side_effect = ClientError(
            {
                "Error": {
                    "Code": "ResourceNotFoundException",
                    "Message": "Secret not found",
                }
            },
            "DescribeSecret",
        )

        with self.assertRaises(ClientError):
            bootstrap.get_existing_application_credentials(
                client, "example-secret-arn"
            )

    def test_application_secret_scheduled_for_deletion(self):
        client = Mock()
        client.get_secret_value.side_effect = ClientError(
            {
                "Error": {
                    "Code": "ResourceNotFoundException",
                    "Message": "Secret version not found",
                }
            },
            "GetSecretValue",
        )
        client.describe_secret.return_value = {
            "DeletedDate": "2026-11-20T00:00:00Z",
            "VersionIdsToStages": {},
        }

        with self.assertRaisesRegex(
            ValueError, "scheduled for deletion"
        ):
            bootstrap.get_existing_application_credentials(
                client, "example-secret-arn"
            )

    def test_prepare_existing_credentials(self):
        existing = {
            "username": "app_user",
            "password": "existing-test-password",
        }

        credentials, is_new = bootstrap.prepare_application_credentials(
            existing
        )

        self.assertEqual(credentials, existing)
        self.assertFalse(is_new)

    def test_prepare_new_credentials(self):
        credentials, is_new = bootstrap.prepare_application_credentials(
            None
        )

        self.assertEqual(credentials["username"], "app_user")
        self.assertTrue(credentials["password"])
        self.assertTrue(is_new)

    def test_prepare_credentials_rejects_invalid_username(self):
        existing = {
            "username": "postgres",
            "password": "example-password",
        }

        with self.assertRaises(ValueError):
            bootstrap.prepare_application_credentials(existing)

    def test_publish_application_credentials(self):
        client = Mock()
        client.put_secret_value.return_value = {
            "VersionId": "test-version-id"
        }

        credentials = {
            "username": "app_user",
            "password": "example-test-password",
        }

        version_id = bootstrap.publish_application_credentials(
            client,
            "example-secret-arn",
            credentials,
        )

        self.assertEqual(version_id, "test-version-id")
        client.put_secret_value.assert_called_once()

        arguments = client.put_secret_value.call_args.kwargs

        self.assertEqual(
            arguments["SecretId"],
            "example-secret-arn",
        )
        self.assertEqual(
            json.loads(arguments["SecretString"]),
            credentials,
        )
        self.assertTrue(arguments["ClientRequestToken"])

    def test_publish_application_credentials_rejects_invalid_username(self):
        client = Mock()

        credentials = {
            "username": "postgres",
            "password": "example-test-password",
        }

        with self.assertRaises(ValueError):
            bootstrap.publish_application_credentials(
                client,
                "example-secret-arn",
                credentials,
            )

        client.put_secret_value.assert_not_called()

    def test_acquire_bootstrap_lock(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value

        bootstrap.acquire_bootstrap_lock(connection)

        cursor.execute.assert_called_once_with(
            "SELECT pg_advisory_xact_lock(%s)",
            (460118,),
        )

    def test_publish_application_credentials_with_stable_token(self):
        client = Mock()
        client.put_secret_value.return_value = {
            "VersionId": "test-version-id"
        }

        credentials = {
            "username": "app_user",
            "password": "example-test-password",
        }

        token = "12345678-1234-4234-8234-123456789012"

        result = bootstrap.publish_application_credentials(
            client,
            "example-secret-arn",
            credentials,
            request_token=token,
        )

        self.assertEqual(result, "test-version-id")

        arguments = client.put_secret_value.call_args.kwargs

        self.assertEqual(arguments["ClientRequestToken"], token)
        self.assertEqual(
            json.loads(arguments["SecretString"]),
            credentials,
        )

        client.put_secret_value.assert_called_once()

    def test_publish_application_credentials_recovers_after_error(self):
        from botocore.exceptions import ClientError

        client = Mock()

        credentials = {
            "username": "app_user",
            "password": "example-test-password",
        }

        token = "12345678-1234-4234-8234-123456789012"

        client.put_secret_value.side_effect = ClientError(
            {
                "Error": {
                    "Code": "InternalServiceError",
                    "Message": "Uncertain publication result",
                }
            },
            "PutSecretValue",
        )

        client.get_secret_value.return_value = {
            "SecretString": json.dumps(credentials),
            "VersionId": token,
        }

        result = bootstrap.publish_application_credentials(
            client,
           "example-secret-arn",
            credentials,
            request_token=token,
        )

        self.assertEqual(result, token)

        client.get_secret_value.assert_called_once_with(
           SecretId="example-secret-arn",
           VersionId=token,
        )

        client.put_secret_value.assert_called_once()


    def test_determine_bootstrap_action(self):
        credentials = {
            "username": "app_user",
            "password": "test-password",
        }

        self.assertEqual(
            bootstrap.determine_bootstrap_action(None, False),
            "initialize",
        )

        self.assertEqual(
            bootstrap.determine_bootstrap_action(credentials, True),
            "reuse",
        )

        self.assertEqual(
            bootstrap.determine_bootstrap_action(credentials, False),
            "recover_role",
        )

        with self.assertRaises(RuntimeError):
            bootstrap.determine_bootstrap_action(None, True)

    def test_main_initialization_workflow(self):
        env = {
            "AWS_REGION": "us-east-1",
            "RDS_HOST": "test-db.example.com",
            "RDS_DATABASE": "appdb",
            "RDS_MASTER_SECRET_ARN": "master-secret",
            "APP_DB_SECRET_ARN": "app-secret",
            "RDS_CA_BUNDLE": "/tmp/test-ca.pem",
        }

        credentials = {
            "username": "app_user",
            "password": "test-password",
        }

        with patch.dict(os.environ, env), \
             patch.object(bootstrap.boto3, "client"), \
             patch.object(bootstrap, "get_secret_json"), \
             patch.object(bootstrap, "connect_to_postgres") as connect, \
             patch.object(bootstrap, "acquire_bootstrap_lock"), \
             patch.object(
                 bootstrap,
                 "get_existing_application_credentials",
                 return_value=None,
             ), \
             patch.object(
                 bootstrap,
                 "postgres_role_exists",
                 return_value=False,
             ), \
             patch.object(
                 bootstrap,
                 "prepare_application_credentials",
                 return_value=(credentials, True),
             ), \
             patch.object(bootstrap, "create_application_role") as create, \
             patch.object(bootstrap, "grant_application_permissions") as grant, \
             patch.object(bootstrap, "publish_application_credentials") as publish, \
             patch.object(bootstrap, "verify_application_credentials") as verify:

            connect.return_value.__enter__.return_value = MagicMock()

            bootstrap.main()

            create.assert_called_once()
            grant.assert_called_once()
            publish.assert_called_once()
            verify.assert_called_once()

    def test_main_rolls_back_when_secret_publish_fails(self):
        env = {
            "AWS_REGION": "us-east-1",
            "RDS_HOST": "test-db.example.com",
            "RDS_DATABASE": "appdb",
            "RDS_MASTER_SECRET_ARN": "master-secret",
            "APP_DB_SECRET_ARN": "app-secret",
            "RDS_CA_BUNDLE": "/tmp/test-ca.pem",
        }

        credentials = {
            "username": "app_user",
            "password": "test-password",
        }

        with patch.dict(os.environ, env), \
             patch.object(bootstrap.boto3, "client"), \
             patch.object(bootstrap, "get_secret_json"), \
             patch.object(bootstrap, "connect_to_postgres") as connect, \
             patch.object(bootstrap, "acquire_bootstrap_lock"), \
             patch.object(
                 bootstrap,
                 "get_existing_application_credentials",
                 return_value=None,
             ), \
             patch.object(
                 bootstrap,
                 "postgres_role_exists",
                 return_value=False,
             ), \
             patch.object(
                 bootstrap,
                 "prepare_application_credentials",
                 return_value=(credentials, True),
             ), \
             patch.object(bootstrap, "create_application_role"), \
             patch.object(bootstrap, "grant_application_permissions"), \
             patch.object(
                 bootstrap,
                 "publish_application_credentials",
                 side_effect=RuntimeError("Secret publishing failed"),
             ), \
             patch.object(bootstrap, "verify_application_credentials") as verify:

            connection = MagicMock()
            connect.return_value.__enter__.return_value = connection

            with self.assertRaisesRegex(
                RuntimeError, "Secret publishing failed"
            ):
                bootstrap.main()

            connection.__exit__.assert_not_called()

            connect.return_value.__exit__.assert_called_once()
            exit_args = connect.return_value.__exit__.call_args.args

            self.assertIs(exit_args[0], RuntimeError)
            verify.assert_not_called()

    def test_main_recovers_role_from_existing_secret(self):
        env = {
            "AWS_REGION": "us-east-1",
            "RDS_HOST": "test-db.example.com",
            "RDS_DATABASE": "appdb",
            "RDS_MASTER_SECRET_ARN": "master-secret",
            "APP_DB_SECRET_ARN": "app-secret",
            "RDS_CA_BUNDLE": "/tmp/test-ca.pem",
        }

        credentials = {
            "username": "app_user",
            "password": "existing-secret-password",
        }

        with patch.dict(os.environ, env), \
             patch.object(bootstrap.boto3, "client"), \
             patch.object(bootstrap, "get_secret_json"), \
             patch.object(bootstrap, "connect_to_postgres") as connect, \
             patch.object(bootstrap, "acquire_bootstrap_lock"), \
             patch.object(
                 bootstrap,
                 "get_existing_application_credentials",
                 return_value=credentials,
             ), \
             patch.object(
                 bootstrap,
                 "postgres_role_exists",
                 return_value=False,
             ), \
             patch.object(bootstrap, "create_application_role") as create, \
             patch.object(bootstrap, "grant_application_permissions") as grant, \
             patch.object(bootstrap, "publish_application_credentials") as publish, \
             patch.object(bootstrap, "verify_application_credentials") as verify:

            connection = MagicMock()
            connect.return_value.__enter__.return_value = connection

            bootstrap.main()

            create.assert_called_once_with(
                connection,
                "app_user",
                "existing-secret-password",
            )

            grant.assert_called_once_with(
                connection,
                "appdb",
                "app_user",
            )

            publish.assert_not_called()
            verify.assert_called_once()

if __name__ == "__main__":
    unittest.main()
