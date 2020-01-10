from typing import Optional
from unittest import TestCase

from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port
from mediawords.util.parse_json import encode_json

from .setup_univision_test import AbstractUnivisionTest, UnivisionTestCredentials


class TestUnivisionLocal(AbstractUnivisionTest, TestCase):
    URL = None
    PORT = None

    __slots__ = [
        '__hs',
    ]

    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()

        cls.PORT = random_unused_port()
        cls.URL = f'http://localhost:{cls.PORT}'

    @classmethod
    def univision_credentials(cls) -> Optional[UnivisionTestCredentials]:
        return UnivisionTestCredentials(
            url=f"{cls.URL}/feed",
            client_id='foo',
            client_secret='bar',
        )

    @classmethod
    def expect_to_find_some_stories(cls) -> bool:
        # Test feed always has stories
        return True

    def setUp(self) -> None:
        super().setUp()

        pages = {
            '/feed': encode_json(
                {
                    'status': 'success',
                    'data': {
                        'title': 'Sample Univision feed',
                        'totalItems': 2,
                        'items': [
                            {
                                'type': 'article',
                                'uid': '00000156-ba02-d374-ab77-feab13e20000',
                                'url': f"{self.URL}/first_article",
                                'publishDate': '2016-08-23T23:32:11-04:00',
                                'updateDate': '2016-08-24T10:09:26-04:00',
                                'title': 'First article: 🍕',  # UTF-8 in the title
                                'description': 'This is the first Univision sample article.',
                            },
                            {
                                'type': 'article',
                                'uid': '00000156-ba73-d5b6-affe-faf77f890000',
                                'url': f"{self.URL}/second_article",
                                'publishDate': '2016-08-23T23:20:13-04:00',
                                'updateDate': '2016-08-24T09:55:40-04:00',
                                'title': 'Second article: 🍔',  # UTF-8 in the title
                                'description': 'This is the second Univision sample article.',
                            },
                        ]
                    }
                }
            ),
            '/first_article': """
                <h1>First article</h1>
                <p>This is the first Univision sample article.</p>
            """,
            '/second_article': """
                <h1>Second article</h1>
                <p>This is the second Univision sample article.</p>
            """,
        }

        self.__hs = HashServer(port=self.PORT, pages=pages)
        self.__hs.start()

    def tearDown(self) -> None:
        self.__hs.stop()
