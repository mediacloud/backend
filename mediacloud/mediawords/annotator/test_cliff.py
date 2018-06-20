import copy
from typing import Union

from mediawords.annotator.cliff import CLIFFAnnotator
from mediawords.test.http.hash_server import HashServer
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.config import get_config as py_get_config, set_config as py_set_config
from mediawords.util.json import encode_json
from mediawords.util.network import random_unused_port
from mediawords.util.sql import sql_now


# noinspection SpellCheckingInspection
class TestCLIFFAnnotator(TestDatabaseWithSchemaTestCase):
    @staticmethod
    def __sample_cliff_response() -> dict:
        return {
            "milliseconds": 231,
            "results": {
                "organizations": [
                    {
                        "count": 2,

                        # Newlines should be replaced to spaces, string should get trimmed
                        "name": " Kansas\nHealth\nInstitute   \n  ",
                    },
                    {
                        "count": 2,

                        # Test whether tags that already exist get merged into one
                        "name": "Kansas Health Institute",
                    },
                    {
                        "count": 3,
                        "name": "Census Bureau",
                    },
                ],
                "people": [
                    {
                        "count": 7,
                        "name": "Tim Huelskamp",
                    },
                    {
                        "count": 5,
                        "name": "a.k.a. Obamacare",
                    },
                ],
                "places": {
                    "focus": {
                        "cities": [
                            {
                                "countryCode": "US",
                                "countryGeoNameId": "6252001",
                                "featureClass": "P",
                                "featureCode": "PPLA2",
                                "id": 5391959,
                                "lat": 37.77493,
                                "lon": -122.41942,
                                "name": "San Francisco",
                                "population": 805235,
                                "score": 1,
                                "stateCode": "CA",
                                "stateGeoNameId": "5332921",
                            },
                            {
                                "countryCode": "US",
                                "countryGeoNameId": "6252001",
                                "featureClass": "P",
                                "featureCode": "PPL",
                                "id": 5327684,
                                "lat": 37.87159,
                                "lon": -122.27275,
                                "name": "Berkeley",
                                "population": 112580,
                                "score": 1,
                                "stateCode": "CA",
                                "stateGeoNameId": "5332921",
                            }
                        ],
                        "countries": [
                            {
                                "countryCode": "US",
                                "countryGeoNameId": "6252001",
                                "featureClass": "A",
                                "featureCode": "PCLI",
                                "id": 6252001,
                                "lat": 39.76,
                                "lon": -98.5,
                                "name": "United States",
                                "population": 310232863,
                                "score": 10,
                                "stateCode": "00",
                                "stateGeoNameId": "",
                            }
                        ],
                        "states": [
                            {
                                "countryCode": "US",
                                "countryGeoNameId": "6252001",
                                "featureClass": "A",
                                "featureCode": "ADM1",
                                "id": 4273857,
                                "lat": 38.50029,
                                "lon": -98.50063,
                                "name": "Kansas",
                                "population": 2740759,
                                "score": 10,
                                "stateCode": "KS",
                                "stateGeoNameId": "4273857",
                            },
                            {
                                "countryCode": "US",
                                "countryGeoNameId": "6252001",
                                "featureClass": "A",
                                "featureCode": "ADM1",
                                "id": 5332921,
                                "lat": 37.25022,
                                "lon": -119.75126,
                                "name": "California",
                                "population": 37691912,
                                "score": 2,
                                "stateCode": "CA",
                                "stateGeoNameId": "5332921",
                            },
                        ],
                    },
                },
                "mentions": [
                    {
                        "confidence": 1,
                        "countryCode": "US",
                        "countryGeoNameId": "6252001",
                        "featureClass": "A",
                        "featureCode": "ADM1",
                        "id": 4273857,
                        "lat": 38.50029,
                        "lon": -98.50063,
                        "name": "Kansas",
                        "population": 2740759,
                        "source": {
                            "charIndex": 162,
                            "string": "Kansas",
                        },
                        "stateCode": "KS",
                        "stateGeoNameId": "4273857",
                    },
                    {
                        "confidence": 1,
                        "countryCode": "US",
                        "countryGeoNameId": "6252001",
                        "featureClass": "P",
                        "featureCode": "PPL",
                        "id": 5327684,
                        "lat": 37.87159,
                        "lon": -122.27275,
                        "name": "Berkeley",
                        "population": 112580,
                        "source": {
                            "charIndex": 6455,
                            "string": "Berkeley",
                        },
                        "stateCode": "CA",
                        "stateGeoNameId": "5332921",
                    },
                ],
            },
            "status": "ok",
            "version": "2.4.1",
        }

    @staticmethod
    def __expected_tags() -> list:
        return [
            {
                'tag_sets_name': 'cliff_organizations',
                'tags_label': 'Census Bureau',
                'tags_name': 'Census Bureau',
                'tags_description': 'Census Bureau',
                'tag_sets_description': 'CLIFF organizations',
                'tag_sets_label': 'cliff_organizations'
            },
            {
                'tags_name': 'Kansas Health Institute',
                'tag_sets_name': 'cliff_organizations',
                'tags_label': " Kansas\nHealth\nInstitute   \n  ",
                'tag_sets_label': 'cliff_organizations',
                'tag_sets_description': 'CLIFF organizations',
                'tags_description': " Kansas\nHealth\nInstitute   \n  "
            },
            {
                'tags_description': 'Tim Huelskamp',
                'tag_sets_label': 'cliff_people',
                'tag_sets_description': 'CLIFF people',
                'tag_sets_name': 'cliff_people',
                'tags_label': 'Tim Huelskamp',
                'tags_name': 'Tim Huelskamp'
            },
            {
                'tags_name': 'a.k.a. Obamacare',
                'tag_sets_name': 'cliff_people',
                'tags_label': 'a.k.a. Obamacare',
                'tag_sets_description': 'CLIFF people',
                'tag_sets_label': 'cliff_people',
                'tags_description': 'a.k.a. Obamacare'
            },
            {
                'tags_description': 'Story was tagged with \'cliff_clavin_v2.4.1\'',
                'tag_sets_label': 'geocoder_version',
                'tag_sets_description': 'CLIFF version the story was tagged with',
                'tags_label': 'cliff_clavin_v2.4.1',
                'tag_sets_name': 'geocoder_version',
                'tags_name': 'cliff_clavin_v2.4.1'
            },
            {
                'tags_label': 'Kansas',
                'tag_sets_name': 'cliff_geonames',
                'tags_name': 'geonames_4273857',
                'tags_description': 'Kansas | A | KS | US',
                'tag_sets_description': 'CLIFF geographical names',
                'tag_sets_label': 'cliff_geonames'
            },
            {
                'tags_label': 'Berkeley',
                'tag_sets_name': 'cliff_geonames',
                'tags_name': 'geonames_5327684',
                'tags_description': 'Berkeley | P | CA | US',
                'tag_sets_description': 'CLIFF geographical names',
                'tag_sets_label': 'cliff_geonames'
            },
            {
                'tags_name': 'geonames_5332921',
                'tag_sets_name': 'cliff_geonames',
                'tags_label': 'California',
                'tag_sets_label': 'cliff_geonames',
                'tag_sets_description': 'CLIFF geographical names',
                'tags_description': 'California | A | CA | US'
            },
            {
                'tag_sets_name': 'cliff_geonames',
                'tags_label': 'San Francisco',
                'tags_name': 'geonames_5391959',
                'tags_description': 'San Francisco | P | CA | US',
                'tag_sets_description': 'CLIFF geographical names',
                'tag_sets_label': 'cliff_geonames'
            },
            {
                'tag_sets_description': 'CLIFF geographical names',
                'tag_sets_label': 'cliff_geonames',
                'tags_description': 'United States | A | US',
                'tags_name': 'geonames_6252001',
                'tags_label': 'United States',
                'tag_sets_name': 'cliff_geonames'
            }
        ]

    def test_cliff_annotator(self):
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

        def __cliff_sample_response(_: HashServer.Request) -> Union[str, bytes]:
            """Mock annotator."""
            response = ""
            response += "HTTP/1.0 200 OK\r\n"
            response += "Content-Type: application/json; charset=UTF-8\r\n"
            response += "\r\n"
            response += encode_json(self.__sample_cliff_response())
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

        # Inject CLIFF credentials into configuration
        config = py_get_config()
        new_config = copy.deepcopy(config)
        new_config['cliff'] = {
            'enabled': True,
            'annotator_url': annotator_url,
        }
        py_set_config(new_config)

        cliff = CLIFFAnnotator()
        cliff.annotate_and_store_for_story(db=self.db(), stories_id=stories_id)
        cliff.update_tags_for_story(db=self.db(), stories_id=stories_id)

        hs.stop()

        # Reset configuration
        py_set_config(config)

        annotation_exists = self.db().query("""
            SELECT 1
            FROM cliff_annotations
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
