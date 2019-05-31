from unittest import TestCase

from utils import container_dir_name_from_image_name, DefaultDockerHubConfiguration, _ordered_container_dependencies


class TestUtils(TestCase):

    def test_container_dir_name_from_image_name(self):
        assert container_dir_name_from_image_name(
            image_name='dockermediacloud/topics-fetch-twitter-urls:latest',
            conf=DefaultDockerHubConfiguration(),
        ) == 'topics-fetch-twitter-urls'

    def test_container_dependency_tree(self):
        dependencies = {
            'extract-and-vector': 'common',
            'crawler': 'common',
            'common': 'base',
            'base': 'ubuntu:16.04',
            'predict-news-labels': 'base',
            'some-other-container': 'alpine:3.9',
        }
        expected_tree = [
            {'alpine:3.9', 'ubuntu:16.04'},
            {'base', 'some-other-container'},
            {'common', 'predict-news-labels'},
            {'crawler', 'extract-and-vector'},
        ]
        got_tree = _ordered_container_dependencies(dependencies)
        assert got_tree == expected_tree

        assert _ordered_container_dependencies(dict()) == []
