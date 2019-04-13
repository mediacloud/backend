from mediawords.test.hash_server import HashServer
from mediawords.util.url.variants import all_url_variants
from tests.python.mediawords.util.url.variants.setup_test_url_variants import TestURLVariantsTestCase


class TestBasic(TestURLVariantsTestCase):

    def test_all_url_variants_basic(self):
        """Basic"""

        pages = {
            '/first': '<meta http-equiv="refresh" content="0; URL=/second%s" />' % self.CRUFT,
            '/second': '<meta http-equiv="refresh" content="0; URL=/third%s" />' % self.CRUFT,
            '/third': 'This is where the redirect chain should end.',
        }

        hs = HashServer(port=self.TEST_HTTP_SERVER_PORT, pages=pages)
        hs.start()
        actual_url_variants = all_url_variants(db=self.db, url=self.STARTING_URL)
        hs.stop()

        assert set(actual_url_variants) == {
            self.STARTING_URL,
            self.STARTING_URL_WITHOUT_CRUFT,
            '%s/third' % self.TEST_HTTP_SERVER_URL,
            '%s/third%s' % (self.TEST_HTTP_SERVER_URL, self.CRUFT,)
        }
