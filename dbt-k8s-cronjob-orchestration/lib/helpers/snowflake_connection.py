import snowflake.connector
import os

try:
    from helpers import aws_secrets
except ImportError:
    from lib.helpers import aws_secrets


class SnowflakeConnection:
    """Snowflake connection wrapper supporting both prod (secrets) and local (SSO) auth."""

    def __init__(self, secret_name='warehouse-credentials', region_name='us-west-2',
                 database=None, schema=None, role=None, warehouse=None):
        secret_name = os.getenv("SECRET_NAME", secret_name)
        self.credentials = aws_secrets.GetSecrets(secret_name, region_name).secrets()
        self.config = {
            "account": self.credentials["account"],
            "user": self.credentials["username"],
            "password": self.credentials["password"],
            "database": database or self.credentials["database"],
            "schema": schema or self.credentials["schema"],
            "warehouse": warehouse or self.credentials["warehouse"],
            "role": role or self.credentials["role"],
        }

    def connection(self):
        return snowflake.connector.connect(**self.config)

    @staticmethod
    def local_connection():
        import subprocess
        git_user = subprocess.check_output(
            "git config --global user.email", shell=True
        ).decode('utf-8').strip()
        return snowflake.connector.connect(
            account='<snowflake-account>',
            user=git_user,
            authenticator='externalbrowser',
            database='DATA_WAREHOUSE_TEST',
            schema='public',
            warehouse='DEV_WH',
            role='DEV_ROLE',
        )
