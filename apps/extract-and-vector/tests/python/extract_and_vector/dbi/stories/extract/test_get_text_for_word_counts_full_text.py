from extract_and_vector.dbi.stories.text import get_text_for_word_counts
from .setup_test_extract import TestExtract


class TestGetTextForWordCountsFullText(TestExtract):

    def test_get_text_for_word_counts_full_text(self):
        """Test get_text_for_word_counts() with full text RSS enabled."""

        self.test_story = self.db.update_by_id(
            table='stories',
            object_id=self.test_story['stories_id'],
            update_hash={
                'title': 'Full text RSS title',
                'description': 'Full text RSS description',
                'full_text_rss': True,
            },
        )

        story_text = get_text_for_word_counts(db=self.db, story=self.test_story)
        assert story_text == "Full text RSS title\n\nFull text RSS description"
