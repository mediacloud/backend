from typing import Union
from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port
from mediawords.util.parse_json import encode_json
from mediawords.util.sql import sql_now

from nytlabels_fetch_annotation_and_tag.config import NYTLabelsTagsFromAnnotationConfig
from nytlabels_fetch_annotation_and_tag.nytlabels_tags_from_annotation import NYTLabelsTagsFromAnnotation
from nytlabels_fetch_annotation_and_tag.sample_data import sample_nytlabels_response, expected_nytlabels_tags


class TestNYTLabelsTagsFromAnnotation(TestCase):

    def test_tagging(self):
        db = connect_to_db()

        media = db.create(table='media', insert_hash={
            'name': "test medium",
            'url': "url://test/medium",
        })

        story = db.create(table='stories', insert_hash={
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

        db.create(table='story_sentences', insert_hash={
            'stories_id': stories_id,
            'sentence_number': 1,
            'sentence': 'I hope that the annotator is working.',
            'media_id': media['media_id'],
            'publish_date': sql_now(),
            'language': 'en'
        })

        def __nyt_labels_sample_response(_: HashServer.Request) -> Union[str, bytes]:
            """Mock annotator."""
            response = ""
            response += "HTTP/1.0 200 OK\r\n"
            response += "Content-Type: application/json; charset=UTF-8\r\n"
            response += "\r\n"
            response += encode_json(sample_nytlabels_response())
            return response

        pages = {
            '/predict.json': {
                'callback': __nyt_labels_sample_response,
            }
        }

        port = random_unused_port()
        annotator_url = 'http://localhost:%d/predict.json' % port

        hs = HashServer(port=port, pages=pages)
        hs.start()

        class TestNYTLabelsFetcherConfig(NYTLabelsTagsFromAnnotationConfig):
            @staticmethod
            def annotator_url() -> str:
                return annotator_url

        nytlabels = NYTLabelsTagsFromAnnotation(tagger_config=TestNYTLabelsFetcherConfig())
        nytlabels.update_tags_for_story(db=db, stories_id=stories_id)

        hs.stop()

        story_tags = db.query("""
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
