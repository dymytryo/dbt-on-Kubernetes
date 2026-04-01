import yaml
import os
import boto3

try:
    from lib.helpers import aws_secrets
except ImportError:
    from helpers import aws_secrets


def create_profile(secrets):
    """Generate profiles.yml from AWS Secrets Manager credentials (production)."""
    target = 'prod'
    main_target = {
        'prod': {
            'type': 'snowflake',
            'account': secrets['account'],
            'user': secrets['username'],
            'password': secrets['password'],
            'role': secrets['role'],
            'warehouse': secrets['warehouse'],
            'database': os.getenv('DATABASE', 'DATA_WAREHOUSE_TEST'),
            'schema': 'public',
            'threads': 4,
            'client_session_keep_alive': False,
            'target': target
        }
    }
    outputs = {'outputs': main_target, 'target': target}
    yaml_dict = {'dbt_etl': outputs}

    with open(r'profiles.yml', 'w') as file:
        yaml.dump(yaml_dict, file)


def create_profile_local(git_user, database_name):
    """Generate profiles.yml for local development (browser SSO auth)."""
    main_target = {
        'prod': {
            'type': 'snowflake',
            'account': '<snowflake-account>',
            'user': git_user,
            'authenticator': 'externalbrowser',
            'role': 'DEV_ROLE',
            'warehouse': 'DEV_WH',
            'database': database_name,
            'schema': 'public',
            'threads': 4,
            'client_session_keep_alive': False,
            'target': 'prod'
        }
    }
    outputs = {'outputs': main_target, 'target': 'prod'}
    yaml_dict = {'dbt_etl': outputs}

    with open(r'profiles.yml', 'w') as file:
        yaml.dump(yaml_dict, file)


def main():
    prod_account = '<aws-prod-account-id>'
    account = boto3.client('sts').get_caller_identity().get('Account')

    if account == prod_account:
        credentials = aws_secrets.GetSecrets(
            os.getenv('SECRET_NAME', 'warehouse-credentials'), 'us-west-2'
        ).secrets()
        create_profile(credentials)
    else:
        import subprocess
        git_user = subprocess.check_output(
            'git config --global user.email', shell=True
        ).decode('utf-8').strip()
        create_profile_local(git_user, 'DATA_WAREHOUSE_TEST')


if __name__ == '__main__':
    main()
