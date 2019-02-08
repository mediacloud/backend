from mediawords.db import DatabaseHandler
# noinspection PyProtectedMember
from mediawords.dbi.stories.stories import (
    is_new,
    add_story,
    _create_child_download_for_story,
)
from mediawords.test.db.create import (
    create_test_medium,
    create_test_feed,
    create_test_story,
    create_test_story_stack,
    create_download_for_feed,
)
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.sql import increment_day


class TestStories(TestDatabaseWithSchemaTestCase):
    TEST_MEDIUM_NAME = 'test medium'
    TEST_FEED_NAME = 'test feed'
    TEST_STORY_NAME = 'test story'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.test_medium = create_test_medium(self.db(), self.TEST_MEDIUM_NAME)
        self.test_feed = create_test_feed(self.db(), self.TEST_FEED_NAME, self.test_medium)
        self.test_download = create_download_for_feed(self.db(), self.test_feed)
        self.test_story = create_test_story(self.db(), label=self.TEST_STORY_NAME, feed=self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.test_download['stories_id'] = self.test_story['stories_id']
        self.db().update_by_id('downloads', self.test_download['downloads_id'], self.test_download)

    def test_is_new(self):

        def _test_story(db: DatabaseHandler, story_: dict, num_: int) -> None:

            assert is_new(
                db=db,
                story=story_,
            ) is False, "{} identical".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'media_id': story['media_id'] + 1,
                }},
            ) is True, "{} media_id diff".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'url': 'diff',
                    'guid': 'diff',
                }},
            ) is False, "{} URL + GUID diff, title same".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'url': 'diff',
                    'title': 'diff',
                }},
            ) is False, "{} title + URL diff, GUID same".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'guid': 'diff',
                    'title': 'diff',
                }},
            ) is True, "{} title + GUID diff, URL same".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'url': 'diff',
                    'guid': 'diff',
                    'publish_date': increment_day(date=story['publish_date'], days=2),
                }},
            ) is True, "{} date + 2 days".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'url': 'diff',
                    'guid': 'diff',
                    'publish_date': increment_day(date=story['publish_date'], days=-2),
                }},
            ) is True, "{} date - 2 days".format(num_)

        data = {
            'A': {
                'B': [1, 2, 3],
                'C': [4, 5, 6],
            },
            'D': {
                'E': [7, 8, 9],
            }
        }

        media = create_test_story_stack(db=self.db(), data=data)
        for media_name, feeds in data.items():
            for feeds_name, stories in feeds.items():
                for num in stories:
                    story = media[media_name]['feeds'][feeds_name]['stories'][str(num)]
                    _test_story(db=self.db(), story_=story, num_=num)

    def test_add_story(self):
        """Test add_story()."""

        media_id = self.test_medium['media_id']
        feeds_id = self.test_feed['feeds_id']

        # Basic story
        story = {
            'media_id': media_id,
            'url': 'http://add.story/',
            'guid': 'http://add.story/',
            'title': 'test add story',
            'description': 'test add story',
            'publish_date': '2016-10-15 08:00:00',
            'collect_date': '2016-10-15 10:00:00',
            'full_text_rss': True,
        }
        added_story = add_story(db=self.db(), story=story, feeds_id=feeds_id)
        assert added_story
        assert 'stories_id' in added_story
        assert story['url'] == added_story['url']
        assert added_story['full_text_rss'] is True

        feeds_stories_tag_mapping = self.db().select(
            table='feeds_stories_map',
            what_to_select='*',
            condition_hash={
                'stories_id': added_story['stories_id'],
                'feeds_id': feeds_id,
            }
        ).hashes()
        assert len(feeds_stories_tag_mapping) == 1

        # Try adding a duplicate story
        added_story = add_story(db=self.db(), story=story, feeds_id=feeds_id)
        assert added_story is None

        # Try adding a duplicate story with explicit "is new" testing disabled
        added_story = add_story(db=self.db(), story=story, feeds_id=feeds_id, skip_checking_if_new=True)
        assert added_story is None

    def test_add_story_full_text_rss(self):
        """Test add_story() with only parent media's full_text_rss set to True."""

        media_id = self.test_medium['media_id']
        feeds_id = self.test_feed['feeds_id']

        self.db().update_by_id(
            table='media',
            object_id=media_id,
            update_hash={'full_text_rss': True},
        )

        story = {
            'media_id': media_id,
            'url': 'http://add.story/',
            'guid': 'http://add.story/',
            'title': 'test add story',
            'description': 'test add story',
            'publish_date': '2016-10-15 08:00:00',
            'collect_date': '2016-10-15 10:00:00',
            # 'full_text_rss' to be inferred from parent "media" item
        }
        added_story = add_story(db=self.db(), story=story, feeds_id=feeds_id)
        assert added_story
        assert 'stories_id' in added_story
        assert story['url'] == added_story['url']
        assert added_story['full_text_rss'] is True

    def test_create_child_download_for_story(self):
        downloads = self.db().query('SELECT * FROM downloads').hashes()
        assert len(downloads) == 1

        _create_child_download_for_story(
            db=self.db(),
            story=self.test_story,
            parent_download=self.test_download,
        )

        downloads = self.db().query('SELECT * FROM downloads').hashes()
        assert len(downloads) == 2

        child_download = self.db().query("""
            SELECT *
            FROM downloads
            WHERE parent = %(parent_downloads_id)s
          """, {'parent_downloads_id': self.test_download['downloads_id']}).hash()
        assert child_download

        assert child_download['feeds_id'] == self.test_feed['feeds_id']
        assert child_download['stories_id'] == self.test_story['stories_id']

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
