#!/usr/bin/env py.test

import abc

from mediawords.key_value_store.test_key_value_store import TestKeyValueStoreTestCase
from mediawords.util.config.common import AmazonS3DownloadsConfig
from mediawords.util.text import random_string


def get_test_s3_credentials() -> AmazonS3DownloadsConfig:
    """Return test Amazon S3 credentials."""

    class AmazonS3DownloadsTestConfig(AmazonS3DownloadsConfig):

        @staticmethod
        def directory_name():
            return '%s-%s'.format(super().directory_name(), random_string(64))

    return AmazonS3DownloadsTestConfig()


test_credentials = get_test_s3_credentials()


class TestAmazonS3CredentialsTestCase(TestKeyValueStoreTestCase, metaclass=abc.ABCMeta):
    pass
