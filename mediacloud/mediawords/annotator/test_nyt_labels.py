import copy
from typing import Union

from mediawords.annotator.nyt_labels import NYTLabelsAnnotator
from mediawords.test.hash_server import HashServer
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.config import get_config as py_get_config, set_config as py_set_config
from mediawords.util.parse_json import encode_json
from mediawords.util.network import random_unused_port
from mediawords.util.sql import sql_now


# noinspection SpellCheckingInspection
class TestNYTLabelsAnnotator(TestDatabaseWithSchemaTestCase):
    @staticmethod
    def __sample_nyt_labels_response() -> dict:
        return {
            "allDescriptors": [
                {
                    "label": "hurricanes and tropical storms",
                    "score": "0.89891",
                },
                {
                    "label": "energy and power",
                    "score": "0.50804"
                }
            ],
            "descriptors3000": [
                {
                    "label": "hurricanes and tropical storms",
                    "score": "0.82505"
                },
                {
                    "label": "hurricane katrina",
                    "score": "0.17088"
                }
            ],

            # Only "descriptors600" are to be used
            "descriptors600": [
                {
                    # Newlines should be replaced to spaces, string should get trimmed
                    "label": " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
                    "score": "0.92481"
                },
                {
                    "label": "electric light and power",
                    "score": "0.10210"  # should be skipped due to threshold
                }
            ],

            "descriptorsAndTaxonomies": [
                {
                    "label": "top/news",
                    "score": "0.82466"
                },
                {
                    "label": "hurricanes and tropical storms",
                    "score": "0.81941"
                }
            ],
            "taxonomies": [
                {
                    "label": "Top/Features/Travel/Guides/Destinations/Caribbean and Bermuda",
                    "score": "0.83390"
                },
                {
                    "label": "Top/News",
                    "score": "0.77210"
                }
            ]
        }

    @staticmethod
    def __expected_tags() -> list:
        return [
            {
                'tag_sets_name': 'nyt_labels',
                'tags_description': " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
                'tag_sets_description': 'NYTLabels labels',
                'tags_label': " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
                'tags_name': 'hurricanes and tropical storms',
                'tag_sets_label': 'nyt_labels'
            },
            {
                'tag_sets_label': 'nyt_labels_version',
                'tags_label': 'nyt_labeller_v1.0.0',
                'tag_sets_description': 'NYTLabels version the story was tagged with',
                'tags_name': 'nyt_labeller_v1.0.0',
                'tag_sets_name': 'nyt_labels_version',
                'tags_description': 'Story was tagged with \'nyt_labeller_v1.0.0\''
            }
        ]

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

        def __nyt_labels_sample_response(_: HashServer.Request) -> Union[str, bytes]:
            """Mock annotator."""
            response = ""
            response += "HTTP/1.0 200 OK\r\n"
            response += "Content-Type: application/json; charset=UTF-8\r\n"
            response += "\r\n"
            response += encode_json(self.__sample_nyt_labels_response())
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

        # Inject NYTLabels credentials into configuration
        config = py_get_config()
        new_config = copy.deepcopy(config)
        new_config['nytlabels'] = {
            'enabled': True,
            'annotator_url': annotator_url,
        }
        py_set_config(new_config)

        nytlabels = NYTLabelsAnnotator()
        nytlabels.annotate_and_store_for_story(db=self.db(), stories_id=stories_id)
        nytlabels.update_tags_for_story(db=self.db(), stories_id=stories_id)

        hs.stop()

        # Reset configuration
        py_set_config(config)

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

        expected_tags = self.__expected_tags()

        assert story_tags == expected_tags
