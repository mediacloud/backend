from mediawords.dbi.stories.stories.setup_test_stories import TestStories
# noinspection PyProtectedMember
from mediawords.dbi.stories.stories import _create_child_download_for_story


class TestCreateChildDownloadForStoryContentDelay(TestStories):

    def test_create_child_download_for_story_content_delay(self):
        """Test create_child_download_for_story() with media.content_delay set."""
        downloads = self.db().query('SELECT * FROM downloads').hashes()
        assert len(downloads) == 1

        content_delay_hours = 3

        self.db().query("""
            UPDATE media
            SET content_delay = %(content_delay)s -- Hours
            WHERE media_id = %(media_id)s
        """, {
            'content_delay': content_delay_hours,
            'media_id': self.test_medium['media_id'],
        })

        _create_child_download_for_story(
            db=self.db(),
            story=self.test_story,
            parent_download=self.test_download,
        )

        parent_download = self.db().query("""
            SELECT EXTRACT(EPOCH FROM download_time)::int AS download_timestamp
            FROM downloads
            WHERE downloads_id = %(downloads_id)s
          """, {'downloads_id': self.test_download['downloads_id']}).hash()
        assert parent_download

        child_download = self.db().query("""
            SELECT EXTRACT(EPOCH FROM download_time)::int AS download_timestamp
            FROM downloads
            WHERE parent = %(parent_downloads_id)s
          """, {'parent_downloads_id': self.test_download['downloads_id']}).hash()
        assert child_download

        time_difference = abs(parent_download['download_timestamp'] - child_download['download_timestamp'])

        # 1. I have no idea in which timezone are downloads being stored (it's definitely not UTC, maybe
        #    America/New_York)
        # 2. It appears that "downloads.download_time" has dual-use: "download not earlier than" for pending downloads,
        #    and "downloaded at" for completed downloads, which makes things more confusing
        #
        # So, in a test, let's just be happy if the download times differ (which might not even be the case depending on
        # server's / database's timezone).
        assert time_difference > 10
