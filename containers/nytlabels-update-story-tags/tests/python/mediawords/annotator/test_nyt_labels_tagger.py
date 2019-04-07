from mediawords.annotator.nyt_labels_tagger import NYTLabelsTagger
from mediawords.annotator.nyt_labels_store import NYTLabelsAnnotatorStore
from mediawords.annotator.sample_data import sample_nytlabels_response, expected_nytlabels_tags
from mediawords.test.testing_database import TestDatabaseTestCase
from mediawords.util.sql import sql_now


class TestNYTLabelsAnnotator(TestDatabaseTestCase):

    def test_nyt_labels_annotator(self):
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

        store = NYTLabelsAnnotatorStore()
        store.store_annotation_for_story(db=self.db(), stories_id=stories_id, annotation=sample_nytlabels_response())

        nytlabels = NYTLabelsTagger()
        nytlabels.update_tags_for_story(db=self.db(), stories_id=stories_id)

        annotation_exists = self.db().query("""
            SELECT 1
            FROM nytlabels_annotations
            WHERE object_id = %(object_id)s
        """, {'object_id': stories_id}).hash()
        assert annotation_exists is not None

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
            ORDER BY tags.tag COLLATE "C", tag_sets.name COLLATE "C"
        """, {'stories_id': stories_id}).hashes()

        expected_tags = expected_nytlabels_tags()

        assert story_tags == expected_tags
