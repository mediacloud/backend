from typing import Union

from mediawords.db import connect_to_db
from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port
from mediawords.util.parse_json import encode_json
from mediawords.util.sql import sql_now
from cliff_base.sample_data import sample_cliff_response
from cliff_fetch_annotation.fetcher import CLIFFAnnotatorFetcher
from cliff_fetch_annotation.config import CLIFFFetcherConfig


def test_cliff_annotator():

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

    class TestCLIFFFetcherConfig(CLIFFFetcherConfig):
        @staticmethod
        def annotator_url() -> str:
            return annotator_url

    cliff = CLIFFAnnotatorFetcher(fetcher_config=TestCLIFFFetcherConfig())
    cliff.annotate_and_store_for_story(db=db, stories_id=stories_id)

    hs.stop()

    annotation_exists = db.query("""
        SELECT 1
        FROM cliff_annotations
        WHERE object_id = %(object_id)s
    """, {'object_id': stories_id}).hash()
    assert annotation_exists is not None
