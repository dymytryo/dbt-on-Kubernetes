import boto3
import json


class GetSecrets:
    """Fetch credentials from AWS Secrets Manager."""

    def __init__(self, secret_name, region_name):
        self.secret_name = secret_name
        self.region_name = region_name

    def secrets(self):
        session = boto3.session.Session()
        client = session.client(
            service_name='secretsmanager',
            region_name=self.region_name
        )
        response = client.get_secret_value(SecretId=self.secret_name)
        return json.loads(response["SecretString"], strict=False)
