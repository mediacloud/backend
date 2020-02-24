import abc
import os
import random
import socket
import time
from typing import Union
from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.test.db.create import create_test_medium, create_test_feed
from mediawords.test.hash_server import HashServer
from mediawords.util.log import create_logger

log = create_logger(__name__)


class AbstractFetchTranscriptTestCase(TestCase, metaclass=abc.ABCMeta):
    __slots__ = [
        'db',
        'hs',
        'stories_id',
        'transcript_fetches',
    ]

    @classmethod
    @abc.abstractmethod
    def input_media_path(cls) -> str:
        """Return full path to input media file."""
        raise NotImplemented("Abstract method")

    @classmethod
    @abc.abstractmethod
    def input_media_mime_type(cls) -> str:
        """Return input media file's MIME type."""
        raise NotImplemented("Abstract method")

    @classmethod
    @abc.abstractmethod
    def story_title_description(cls) -> str:
        """Return a string to store as both story title and description."""
        raise NotImplemented("Abstract method")

    @classmethod
    @abc.abstractmethod
    def retries_per_step(cls) -> int:
        """How many retries to do per each local step."""
        raise NotImplemented("Abstract method")

    @classmethod
    @abc.abstractmethod
    def seconds_between_retries(cls) -> float:
        """How many seconds to wait between retries."""
        raise NotImplemented("Abstract method")

    def setUp(self) -> None:
        super().setUp()

        self.db = connect_to_db()

        test_medium = create_test_medium(db=self.db, label='test')
        test_feed = create_test_feed(db=self.db, label='test', medium=test_medium)

        # Add a story with a random ID to decrease the chance that object in GCS will collide with another test running
        # at the same time
        self.stories_id = random.randint(1, 1000000)

        self.db.query("""
            INSERT INTO stories (
                stories_id,
                media_id,
                url,
                guid,
                title,
                description,
                publish_date,
                collect_date,
                full_text_rss
            ) VALUES (
                %(stories_id)s,
                %(media_id)s,
                'http://story.test/',
                'guid://story.test/',
                'story',
                'description',
                '2016-10-15 08:00:00',
                '2016-10-15 10:00:00',
                true
            )
        """, {
            'stories_id': self.stories_id,
            'media_id': test_feed['media_id'],
        })

        # Create missing partitions for "feeds_stories_map"
        self.db.query('SELECT create_missing_partitions()')

        self.db.create(
            table='feeds_stories_map',
            insert_hash={
                'feeds_id': int(test_feed['feeds_id']),
                'stories_id': self.stories_id,
            }
        )

        assert os.path.isfile(self.input_media_path()), f"Test media file '{self.input_media_path()}' should exist."

        with open(self.input_media_path(), mode='rb') as f:
            test_data = f.read()

        # noinspection PyUnusedLocal
        def __media_callback(request: HashServer.Request) -> Union[str, bytes]:
            response = "".encode('utf-8')
            response += "HTTP/1.0 200 OK\r\n".encode('utf-8')
            response += f"Content-Type: {self.input_media_mime_type()}\r\n".encode('utf-8')
            response += f"Content-Length: {len(test_data)}\r\n".encode('utf-8')
            response += "\r\n".encode('utf-8')
            response += test_data
            return response

        port = 8080  # Port exposed on docker-compose.tests.yml
        media_path = '/test_media_file'
        pages = {
            media_path: {
                'callback': __media_callback,
            }
        }

        self.hs = HashServer(port=port, pages=pages)
        self.hs.start()

        # Using our hostname as it will be another container that will be connecting to us
        media_url = f'http://{socket.gethostname()}:{port}{media_path}'

        self.db.insert(table='story_enclosures', insert_hash={
            'stories_id': self.stories_id,
            'url': media_url,
            'mime_type': self.input_media_mime_type(),
            'length': len(test_data),
        })

        # Add a "podcast-fetch-episode" job
        JobBroker(queue_name='MediaWords::Job::Podcast::FetchEpisode').add_to_queue(stories_id=self.stories_id)

        total_time = int(self.retries_per_step() * self.seconds_between_retries())

        # Wait for "podcast-fetch-episode" to transcode, upload to Google Storage, and write it to "podcast_episodes"
        episodes = None
        for x in range(1, self.retries_per_step() + 1):
            log.info(f"Waiting for episode to appear (#{x})...")

            episodes = self.db.select(table='podcast_episodes', what_to_select='*').hashes()
            if episodes:
                log.info(f"Episode is here!")
                break

            time.sleep(self.seconds_between_retries())

        assert episodes, f"Episode didn't show up in {total_time} seconds."

        # Wait for "podcast-submit-operation" to submit Speech API operation
        self.transcript_fetches = None
        for x in range(1, self.retries_per_step() + 1):
            log.info(f"Waiting for transcript fetch to appear (#{x})...")

            self.transcript_fetches = self.db.select(
                table='podcast_episode_transcript_fetches',
                what_to_select='*'
            ).hashes()

            if self.transcript_fetches:
                log.info(f"Transcript fetch is here!")
                break

            time.sleep(self.seconds_between_retries())

        assert self.transcript_fetches, f"Operation didn't show up in {total_time} seconds."

    def tearDown(self) -> None:
        super().tearDown()

        self.hs.stop()
