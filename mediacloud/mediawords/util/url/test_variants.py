import pytest

from mediawords.test.db.create import create_test_story_stack, create_test_topic
from mediawords.test.http.hash_server import HashServer
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.network import random_unused_port
from mediawords.util.url import urls_are_equal
# noinspection PyProtectedMember
from mediawords.util.url.variants import all_url_variants, McAllURLVariantsException


class TestURLVariants(TestDatabaseWithSchemaTestCase):
    # Cruft that we expect the function to remove
    CRUFT = '?utm_source=A&utm_medium=B&utm_campaign=C'

    def setUp(self):
        super().setUp()

        self.TEST_HTTP_SERVER_PORT = random_unused_port()
        self.TEST_HTTP_SERVER_URL = 'http://localhost:%d' % self.TEST_HTTP_SERVER_PORT

        self.STARTING_URL_WITHOUT_CRUFT = '%s/first' % self.TEST_HTTP_SERVER_URL
        self.STARTING_URL = self.STARTING_URL_WITHOUT_CRUFT + self.CRUFT

    def test_all_url_variants_bad_input(self):
        """Erroneous input"""
        # Undefined URL
        with pytest.raises(McAllURLVariantsException):
            # noinspection PyTypeChecker
            all_url_variants(db=self.db(), url=None)

        # Non-HTTP(S) URL
        gopher_url = 'gopher://gopher.floodgap.com/0/v2/vstat'
        assert set(all_url_variants(db=self.db(), url=gopher_url)) == {gopher_url}

    def test_all_url_variants_basic(self):
        """Basic"""

        pages = {
            '/first': '<meta http-equiv="refresh" content="0; URL=/second%s" />' % self.CRUFT,
            '/second': '<meta http-equiv="refresh" content="0; URL=/third%s" />' % self.CRUFT,
            '/third': 'This is where the redirect chain should end.',
        }

        hs = HashServer(port=self.TEST_HTTP_SERVER_PORT, pages=pages)
        hs.start()
        actual_url_variants = all_url_variants(db=self.db(), url=self.STARTING_URL)
        hs.stop()

        assert set(actual_url_variants) == {
            self.STARTING_URL,
            self.STARTING_URL_WITHOUT_CRUFT,
            '%s/third' % self.TEST_HTTP_SERVER_URL,
            '%s/third%s' % (self.TEST_HTTP_SERVER_URL, self.CRUFT,)
        }

    def test_all_url_variants_link_canonical(self):
        """<link rel="canonical" />"""
        pages = {
            '/first': '<meta http-equiv="refresh" content="0; URL=/second%s" />' % self.CRUFT,
            '/second': '<meta http-equiv="refresh" content="0; URL=/third%s" />' % self.CRUFT,
            '/third': '<link rel="canonical" href="%s/fourth" />' % self.TEST_HTTP_SERVER_URL,
        }
        hs = HashServer(port=self.TEST_HTTP_SERVER_PORT, pages=pages)
        hs.start()
        actual_url_variants = all_url_variants(db=self.db(), url=self.STARTING_URL)
        hs.stop()

        assert set(actual_url_variants) == {
            self.STARTING_URL,
            self.STARTING_URL_WITHOUT_CRUFT,
            '%s/third' % self.TEST_HTTP_SERVER_URL,
            '%s/third%s' % (self.TEST_HTTP_SERVER_URL, self.CRUFT,),
            '%s/fourth' % self.TEST_HTTP_SERVER_URL,
        }

    def test_all_url_variants_redirect_to_homepage(self):
        """Redirect to a homepage"""
        pages = {
            '/first': '<meta http-equiv="refresh" content="0; URL=/second%s" />' % self.CRUFT,
            '/second': '<meta http-equiv="refresh" content="0; URL=/',
        }
        hs = HashServer(port=self.TEST_HTTP_SERVER_PORT, pages=pages)
        hs.start()
        actual_url_variants = all_url_variants(db=self.db(), url=self.STARTING_URL)
        hs.stop()

        assert set(actual_url_variants) == {
            self.STARTING_URL,
            self.STARTING_URL_WITHOUT_CRUFT,
            '%s/second' % self.TEST_HTTP_SERVER_URL,
            '%s/second%s' % (self.TEST_HTTP_SERVER_URL, self.CRUFT,),
        }

    def test_all_url_variants_invalid_variants(self):
        """Invalid URL variant (suspended Twitter account)"""
        invalid_url_variant = 'https://twitter.com/Todd__Kincannon/status/518499096974614529'
        actual_url_variants = all_url_variants(db=self.db(), url=invalid_url_variant)
        assert set(actual_url_variants) == {
            invalid_url_variant,
        }

    def test_get_topic_url_variants(self):
        media = create_test_story_stack(
            db=self.db(),
            data={
                'A': {
                    'B': [1, 2, 3],
                    'C': [4, 5, 6],
                },
                'D': {
                    'E': [7, 8, 9],
                }
            }
        )

        story_1 = media['A']['feeds']['B']['stories']['1']
        story_2 = media['A']['feeds']['B']['stories']['2']
        story_3 = media['A']['feeds']['B']['stories']['3']
        story_4 = media['A']['feeds']['C']['stories']['4']

        self.db().query("""
            INSERT INTO topic_merged_stories_map (source_stories_id, target_stories_id)
            VALUES (%(source_stories_id)s, %(target_stories_id)s)
        """, {
            'source_stories_id': story_2['stories_id'],
            'target_stories_id': story_1['stories_id'],
        })

        self.db().query("""
            INSERT INTO topic_merged_stories_map (source_stories_id, target_stories_id)
            VALUES (%(source_stories_id)s, %(target_stories_id)s)
        """, {
            'source_stories_id': story_3['stories_id'],
            'target_stories_id': story_2['stories_id'],
        })

        self.db().create(
            table='tag_sets',
            insert_hash={'name': 'foo'},
        )

        topic = create_test_topic(db=self.db(), label='foo')

        self.db().create(
            table='topic_stories',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_4['stories_id'],
            }
        )

        self.db().create(
            table='topic_stories',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_1['stories_id'],
            }
        )

        self.db().create(
            table='topic_links',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_4['stories_id'],
                'ref_stories_id': story_1['stories_id'],
                'url': story_1['url'],
                'redirect_url': story_1['url'] + "/redirect_url",
            }
        )

        self.db().create(
            table='topic_stories',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_2['stories_id'],
            }
        )

        self.db().create(
            table='topic_links',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_4['stories_id'],
                'ref_stories_id': story_2['stories_id'],
                'url': story_2['url'],
                'redirect_url': story_2['url'] + "/redirect_url",
            }
        )

        self.db().create(
            table='topic_stories',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_3['stories_id']
            }
        )

        self.db().create(
            table='topic_links',
            insert_hash={
                'topics_id': topic['topics_id'],
                'stories_id': story_4['stories_id'],
                'ref_stories_id': story_3['stories_id'],
                'url': story_3['url'] + '/alternate',
            }
        )

        test_url = story_1['url'] + self.CRUFT

        expected_urls = {
            story_1['url'],
            story_1['url'] + self.CRUFT,
            story_2['url'],
            story_1['url'] + "/redirect_url",
            story_2['url'] + "/redirect_url",
            story_3['url'],
            story_3['url'] + "/alternate",
        }

        url_variants = all_url_variants(db=self.db(), url=test_url)

        assert len(expected_urls) == len(url_variants)

        sorted_expected_urls = sorted(expected_urls)
        sorted_url_variants = sorted(url_variants)

        for i in range(len(sorted_expected_urls)):
            assert urls_are_equal(url1=sorted_expected_urls[i], url2=sorted_url_variants[i])
