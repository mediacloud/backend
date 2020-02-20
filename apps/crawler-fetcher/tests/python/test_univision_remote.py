import os
from typing import Optional
from unittest import TestCase

import pytest

from crawler_fetcher.config import CrawlerConfig

from .setup_univision_test import AbstractUnivisionTest, UnivisionTestCredentials


def get_univision_credentials() -> Optional[UnivisionTestCredentials]:
    config = CrawlerConfig()
    client_id = config.univision_client_id()
    client_secret = config.univision_client_secret()

    feed_url = os.environ.get('MC_UNIVISION_TEST_URL', None)

    if feed_url and client_id and client_secret:
        return UnivisionTestCredentials(
            url=feed_url,
            client_id=client_id,
            client_secret=client_secret,
        )
    else:
        return None


@pytest.mark.skipif(get_univision_credentials() is None, reason="Univision test credentials are not set")
class TestUnivisionRemote(AbstractUnivisionTest, TestCase):

    @classmethod
    def univision_credentials(cls) -> Optional[UnivisionTestCredentials]:
        return get_univision_credentials()

    @classmethod
    def expect_to_find_some_stories(cls) -> bool:
        # Live feed sometimes doesn't have any stories
        return False
