from mediawords.dbi.download_texts import create
from mediawords.test.db.create import create_test_medium, create_test_feed, create_download_for_feed
from mediawords.test.testing_database import TestDatabaseTestCase


class TestDownloadTexts(TestDatabaseTestCase):

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.test_medium = create_test_medium(self.db(), 'downloads test')
        self.test_feed = create_test_feed(self.db(), 'downloads test', self.test_medium)
        self.test_download = create_download_for_feed(self.db(), self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.db().update_by_id('downloads', self.test_download['downloads_id'], self.test_download)

    def test_create(self):
        assert len(self.db().query("""
            SELECT *
            FROM download_texts
            WHERE downloads_id = %(downloads_id)s
        """, {'downloads_id': self.test_download['downloads_id']}).hashes()) == 0

        assert len(self.db().query("""
            SELECT *
            FROM downloads
            WHERE downloads_id = %(downloads_id)s
              AND extracted = 't'
        """, {'downloads_id': self.test_download['downloads_id']}).hashes()) == 0

        extract = {
            'extracted_text': 'Hello!',
        }

        created_download_text = create(db=self.db(), download=self.test_download, extract=extract)
        assert created_download_text
        assert created_download_text['downloads_id'] == self.test_download['downloads_id']

        found_download_texts = self.db().query("""
            SELECT *
            FROM download_texts
            WHERE downloads_id = %(downloads_id)s
        """, {'downloads_id': self.test_download['downloads_id']}).hashes()
        assert len(found_download_texts) == 1

        download_text = found_download_texts[0]
        assert download_text
        assert download_text['downloads_id'] == self.test_download['downloads_id']
        assert download_text['download_text'] == extract['extracted_text']
        assert download_text['download_text_length'] == len(extract['extracted_text'])
