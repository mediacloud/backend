from mediawords.dbi.stories.extract import (
    _get_extracted_text,
    get_text_for_word_counts,
)
from mediawords.test.db.create import create_test_medium, create_test_feed, create_download_for_feed, create_test_story
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase


class TestExtract(TestDatabaseWithSchemaTestCase):
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

        extracted_text = _get_extracted_text(db=self.db(), story=self.test_story)
        assert extracted_text == "Text 1.\n\nText 2.\n\nText 3"

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
