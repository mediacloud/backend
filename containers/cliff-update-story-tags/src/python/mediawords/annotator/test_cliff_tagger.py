from mediawords.annotator.cliff_tagger import CLIFFTagger
from mediawords.annotator.cliff_store import CLIFFAnnotatorStore
from mediawords.annotator.sample_data import sample_cliff_response, expected_cliff_tags
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.sql import sql_now


class TestCLIFFTagger(TestDatabaseWithSchemaTestCase):

    def test_cliff_tagger(self):
        media = self.db().create(table='media', insert_hash={
            'name': "test medium",
            'url': "url://test/medium",
        })

        story = self.db().create(table='stories', insert_hash={
            'media_id': media['media_id'],
            'url': 'url://story/a',
            'guid': 'guid://story/a',
            'title': 'story a',
            'description': 'description a',
            'publish_date': sql_now(),
            'collect_date': sql_now(),
            'full_text_rss': True,
        })
        stories_id = story['stories_id']

        self.db().create(table='story_sentences', insert_hash={
            'stories_id': stories_id,
            'sentence_number': 1,
            'sentence': 'I hope that the CLIFF annotator is working.',
            'media_id': media['media_id'],
            'publish_date': sql_now(),
            'language': 'en'
        })

        store = CLIFFAnnotatorStore()
        store.store_annotation_for_story(db=self.db(), stories_id=stories_id, annotation=sample_cliff_response())

        cliff = CLIFFTagger()
        cliff.update_tags_for_story(db=self.db(), stories_id=stories_id)

        story_tags = self.db().query("""
            SELECT
                tags.tag AS tags_name,
                tags.label AS tags_label,
                tags.description AS tags_description,
                tag_sets.name AS tag_sets_name,
                tag_sets.label AS tag_sets_label,
                tag_sets.description AS tag_sets_description
            FROM stories_tags_map
                INNER JOIN tags
                    ON stories_tags_map.tags_id = tags.tags_id
                INNER JOIN tag_sets
                    ON tags.tag_sets_id = tag_sets.tag_sets_id
            WHERE stories_tags_map.stories_id = %(stories_id)s
            ORDER BY
                lower(tag_sets.name),
                lower(tags.tag)
        """, {'stories_id': stories_id}).hashes()

        expected_tags = expected_cliff_tags()

        assert story_tags == expected_tags
