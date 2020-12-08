from typing import Union

from cliff_fetch_annotation_and_tag.cliff_tags_from_annotation import CLIFFTagsFromAnnotation
from cliff_fetch_annotation_and_tag.config import CLIFFTagsFromAnnotationConfig
from cliff_fetch_annotation_and_tag.sample_data import sample_cliff_response, expected_cliff_tags
from mediawords.db import connect_to_db
from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port
from mediawords.util.parse_json import encode_json
from mediawords.util.sql import sql_now


def test_tagging():
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
        'sentence': 'I hope that the CLIFF annotator is working.',
        'media_id': media['media_id'],
        'publish_date': sql_now(),
        'language': 'en'
    })

    def __cliff_sample_response(_: HashServer.Request) -> Union[str, bytes]:
        """Mock annotator."""
        response = ""
        response += "HTTP/1.0 200 OK\r\n"
        response += "Content-Type: application/json; charset=UTF-8\r\n"
        response += "\r\n"
        response += encode_json(sample_cliff_response())
        return response

    pages = {
        '/cliff/parse/text': {
            'callback': __cliff_sample_response,
        }
    }

    port = random_unused_port()
    annotator_url = 'http://localhost:%d/cliff/parse/text' % port

    hs = HashServer(port=port, pages=pages)
    hs.start()

    class TestCLIFFFetcherConfig(CLIFFTagsFromAnnotationConfig):
        @staticmethod
        def annotator_url() -> str:
            return annotator_url

    cliff = CLIFFTagsFromAnnotation(tagger_config=TestCLIFFFetcherConfig())
    cliff.update_tags_for_story(db=db, stories_id=stories_id)

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
        ORDER BY
            lower(tag_sets.name),
            lower(tags.tag)
    """, {'stories_id': stories_id}).hashes()

    expected_tags = expected_cliff_tags()

    assert story_tags == expected_tags
