import os
from typing import Optional

import pytest

from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.similarweb.media import update_estimated_visits_for_media_id
from mediawords.util.text import random_string


def _similarweb_test_api_key() -> Optional[str]:
    """Return test API key for SimilarWeb."""
    return os.environ.get('MC_SIMILARWEB_TEST_API_KEY', None)


@pytest.mark.skipif(not _similarweb_test_api_key(), reason="SimilarWeb test API key is not set.")
class TestSimilarWebMedia(TestDatabaseWithSchemaTestCase):

    def test_update_estimated_visits_for_media_id(self):
        test_medium = self.db().create(
            table='media',
            insert_hash={
                'name': 'New York Times',
                'url': 'https://www.nytimes.com/',
            })

        media_id = test_medium['media_id']

        update_estimated_visits_for_media_id(
            db=self.db(),
            media_id=media_id,
            api_key=_similarweb_test_api_key(),
        )

        domains = self.db().select(table='similarweb_domains', what_to_select='*').hashes()
        assert len(domains) == 1
        assert domains[0]['domain'] == 'nytimes.com'
        domains_id = domains[0]['similarweb_domains_id']

        domain_media_map = self.db().select(table='media_similarweb_domains_map', what_to_select='*').hashes()
        assert len(domain_media_map) == 1
        assert domain_media_map[0]['media_id'] == media_id
        assert domain_media_map[0]['similarweb_domains_id'] == domains_id

        visits = self.db().select(table='similarweb_estimated_visits', what_to_select='*').hashes()
        assert len(visits) == 12
        assert visits[0]['similarweb_domains_id'] == domains_id

        # Try fetching stats again, make sure it doesn't get refetched
        update_estimated_visits_for_media_id(
            db=self.db(),
            media_id=media_id,
            api_key=_similarweb_test_api_key(),
        )

        domains = self.db().select(table='similarweb_domains', what_to_select='*').hashes()
        assert len(domains) == 1

        domain_media_map = self.db().select(table='media_similarweb_domains_map', what_to_select='*').hashes()
        assert len(domain_media_map) == 1

        visits = self.db().select(table='similarweb_estimated_visits', what_to_select='*').hashes()
        assert len(visits) == 12

    def test_update_estimated_visits_for_media_id_nonexistent_domain(self):

        nonexistent_domain = random_string(length=32).lower() + '.com'

        test_medium = self.db().create(
            table='media',
            insert_hash={
                'name': 'Nonexistent domain',
                'url': f'https://www.{nonexistent_domain}/',
            })

        media_id = test_medium['media_id']

        update_estimated_visits_for_media_id(
            db=self.db(),
            media_id=media_id,
            api_key=_similarweb_test_api_key(),
        )

        domains = self.db().select(table='similarweb_domains', what_to_select='*').hashes()
        assert len(domains) == 1
        assert domains[0]['domain'] == nonexistent_domain
        domains_id = domains[0]['similarweb_domains_id']

        domain_media_map = self.db().select(table='media_similarweb_domains_map', what_to_select='*').hashes()
        assert len(domain_media_map) == 1
        assert domain_media_map[0]['media_id'] == media_id
        assert domain_media_map[0]['similarweb_domains_id'] == domains_id

        visits = self.db().select(table='similarweb_estimated_visits', what_to_select='*').hashes()
        assert len(visits) == 0

        # Try fetching stats again, make sure it doesn't get refetched
        update_estimated_visits_for_media_id(
            db=self.db(),
            media_id=media_id,
            api_key=_similarweb_test_api_key(),
        )

        domains = self.db().select(table='similarweb_domains', what_to_select='*').hashes()
        assert len(domains) == 1

        domain_media_map = self.db().select(table='media_similarweb_domains_map', what_to_select='*').hashes()
        assert len(domain_media_map) == 1

        visits = self.db().select(table='similarweb_estimated_visits', what_to_select='*').hashes()
        assert len(visits) == 0
