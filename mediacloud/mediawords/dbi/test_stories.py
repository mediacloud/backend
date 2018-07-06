from mediawords.db import DatabaseHandler
from mediawords.dbi.stories import (
    mark_as_processed,
    is_new,
    combine_story_title_description_text,
    get_extracted_text,
    add_story,
    get_text_for_word_counts,
)
from mediawords.test.db import (
    create_test_medium,
    create_test_feed,
    create_test_story,
    create_test_story_stack,
    create_download_for_feed,
)
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.sql import increment_day


class TestStories(TestDatabaseWithSchemaTestCase):

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.test_medium = create_test_medium(self.db(), 'downloads test')
        self.test_feed = create_test_feed(self.db(), 'downloads test', self.test_medium)
        self.test_story = create_test_story(self.db(), label='downloads est', feed=self.test_feed)

    def test_mark_as_processed(self):
        processed_stories = self.db().query("SELECT * FROM processed_stories").hashes()
        assert len(processed_stories) == 0

        mark_as_processed(db=self.db(), stories_id=self.test_story['stories_id'])

        processed_stories = self.db().query("SELECT * FROM processed_stories").hashes()
        assert len(processed_stories) == 1
        assert processed_stories[0]['stories_id'] == self.test_story['stories_id']

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

    def test_get_extracted_text(self):
        download_texts = [
            'Text 1',
            'Text 2',
            'Text 3',
        ]

        for download_text in download_texts:
            test_download = create_download_for_feed(self.db(), self.test_feed)
            downloads_id = test_download['downloads_id']

            self.db().update_by_id(
                table='downloads',
                object_id=downloads_id,
                update_hash={
                    'stories_id': self.test_story['stories_id'],
                }
            )
            self.db().create(
                table='download_texts',
                insert_hash={
                    'downloads_id': downloads_id,
                    'download_text': download_text,
                    'download_text_length': len(download_text),
                })

        extracted_text = get_extracted_text(db=self.db(), story=self.test_story)
        assert extracted_text == "Text 1.\n\nText 2.\n\nText 3"

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

    def test_get_text_for_word_counts_full_text(self):
        """Test get_text_for_word_counts() with full text RSS enabled."""

        self.test_story = self.db().update_by_id(
            table='stories',
            object_id=self.test_story['stories_id'],
            update_hash={
                'title': 'Full text RSS title',
                'description': 'Full text RSS description',
                'full_text_rss': True,
            },
        )

        story_text = get_text_for_word_counts(db=self.db(), story=self.test_story)
        assert story_text == "Full text RSS title\n\nFull text RSS description"

    def test_get_text_for_word_counts_not_full_text(self):
        """Test get_text_for_word_counts() with full text RSS disabled."""

        story_description = 'Not full text RSS description'
        download_texts = [
            'Not full text 1',
            'Not full text 2',
            'Not full text 3',
        ]
        assert len(story_description) < len("\n\n".join(download_texts))

        self.test_story = self.db().update_by_id(
            table='stories',
            object_id=self.test_story['stories_id'],
            update_hash={
                'title': 'Not full text RSS title',
                'description': story_description,
                'full_text_rss': False,
            },
        )

        for download_text in download_texts:
            test_download = create_download_for_feed(self.db(), self.test_feed)
            downloads_id = test_download['downloads_id']

            self.db().update_by_id(
                table='downloads',
                object_id=downloads_id,
                update_hash={
                    'stories_id': self.test_story['stories_id'],
                }
            )
            self.db().create(
                table='download_texts',
                insert_hash={
                    'downloads_id': downloads_id,
                    'download_text': download_text,
                    'download_text_length': len(download_text),
                })

        story_text = get_text_for_word_counts(db=self.db(), story=self.test_story)
        assert story_text == "Not full text 1.\n\nNot full text 2.\n\nNot full text 3"


def test_combine_story_title_description_text():
    combined = combine_story_title_description_text(
        story_title='<strong>Title</strong>',
        story_description='<em>Description</em>',
        download_texts=[
            'Text 1',
            'Text 2',
        ]
    )
    assert combined == "Title\n***\n\nDescription\n***\n\nText 1\n***\n\nText 2"
