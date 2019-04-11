#!/usr/bin/env py.test

from mediawords.dbi.stories.extract import get_text_for_word_counts
from mediawords.test.db.create import create_download_for_story
from mediawords.dbi.stories.extract.setup_test_extract import TestExtract


class TestGetTextForWordCountsNotFullText(TestExtract):

    def test_get_text_for_word_counts_not_full_text(self):
        """Test get_text_for_word_counts() with full text RSS disabled."""

        story_description = 'Not full text RSS description'
        download_texts = [
            'Not full text 1',
            'Not full text 2',
            'Not full text 3',
        ]
        assert len(story_description) < len("\n\n".join(download_texts))

        self.test_story = self.db.update_by_id(
            table='stories',
            object_id=self.test_story['stories_id'],
            update_hash={
                'title': 'Not full text RSS title',
                'description': story_description,
                'full_text_rss': False,
            },
        )

        for download_text in download_texts:
            test_download = create_download_for_story(self.db, feed=self.test_feed, story=self.test_story)
            downloads_id = test_download['downloads_id']

            self.db.create(
                table='download_texts',
                insert_hash={
                    'downloads_id': downloads_id,
                    'download_text': download_text,
                    'download_text_length': len(download_text),
                })

        story_text = get_text_for_word_counts(db=self.db, story=self.test_story)
        assert story_text == "Not full text 1.\n\nNot full text 2.\n\nNot full text 3"
