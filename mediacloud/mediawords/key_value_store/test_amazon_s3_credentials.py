import abc
import copy
import os
from typing import Union

import pytest

from mediawords.key_value_store.test_key_value_store import TestKeyValueStoreTestCase
from mediawords.util.config import get_config as py_get_config
from mediawords.util.text import random_string


def get_test_s3_credentials() -> Union[dict, None]:
    """Return test Amazon S3 credentials as a dictionary or None if credentials are not configured."""

    config = py_get_config()

    credentials = None

    # Environment variables
    if os.getenv('MC_AMAZON_S3_TEST_ACCESS_KEY_ID') is not None:
        credentials = {
            'access_key_id': os.getenv('MC_AMAZON_S3_TEST_ACCESS_KEY_ID', None),
            'secret_access_key': os.getenv('MC_AMAZON_S3_TEST_SECRET_ACCESS_KEY', None),
            'bucket_name': os.getenv('MC_AMAZON_S3_TEST_BUCKET_NAME', None),
            'directory_name': os.getenv('MC_AMAZON_S3_TEST_DIRECTORY_NAME', None),
        }

    # mediawords.yml
    elif 'amazon_s3' in config and 'test' in config['amazon_s3']:
        credentials = copy.deepcopy(config['amazon_s3']['test'])

    # We want to be able to run S3 tests in parallel
    if credentials is not None:
        credentials['directory_name'] = credentials['directory_name'] + '-' + random_string(64)

    return credentials


test_credentials = get_test_s3_credentials()

pytest_amazon_s3_credentials_set = pytest.mark.skipif(
    test_credentials is None,
    reason="Amazon S3 test credentials are not set in environment / configuration"
)


@pytest_amazon_s3_credentials_set
class TestAmazonS3CredentialsTestCase(TestKeyValueStoreTestCase, metaclass=abc.ABCMeta):
    pass
