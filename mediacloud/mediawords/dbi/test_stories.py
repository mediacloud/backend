from mediawords.db import DatabaseHandler
from mediawords.dbi.stories import mark_as_processed, is_new, combine_story_title_description_text, get_extracted_text
from mediawords.test.db import create_test_medium, create_test_feed, create_test_story, create_test_story_stack, \
    create_download_for_feed
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
