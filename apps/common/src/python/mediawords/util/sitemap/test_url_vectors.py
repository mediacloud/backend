from unittest import TestCase

from mediawords.util.sitemap.url_vectors import URLFeatureExtractor


class TestURLFeatureExtractor(TestCase):

    def test_path_ends_with_html_extension(self):
        assert URLFeatureExtractor('http://example.com')._path_ends_with_html_extension() is False
        assert URLFeatureExtractor('http://example.html')._path_ends_with_html_extension() is False
        assert URLFeatureExtractor('http://example.com/')._path_ends_with_html_extension() is False
        assert URLFeatureExtractor('http://example.com/test')._path_ends_with_html_extension() is False

        assert URLFeatureExtractor('http://example.com/test.html')._path_ends_with_html_extension() is True
        assert URLFeatureExtractor('http://example.com/.html')._path_ends_with_html_extension() is True
        assert URLFeatureExtractor('http://example.com/test/test.htm')._path_ends_with_html_extension() is True
        assert URLFeatureExtractor('http://example.com/test/test.html')._path_ends_with_html_extension() is True
        assert URLFeatureExtractor('http://example.com/test/test.html/')._path_ends_with_html_extension() is True
        assert URLFeatureExtractor('http://example.com/test/test.html//')._path_ends_with_html_extension() is True

        assert URLFeatureExtractor('http://example.com/test.html/test')._path_ends_with_html_extension() is False

    def test_path_ends_with_slash(self):
        assert URLFeatureExtractor('http://example.com')._path_ends_with_slash() is True
        assert URLFeatureExtractor('http://example.com/')._path_ends_with_slash() is True
        assert URLFeatureExtractor('http://example.com/abc/')._path_ends_with_slash() is True
        assert URLFeatureExtractor('http://example.com/abc/def/')._path_ends_with_slash() is True

        assert URLFeatureExtractor('http://example.com/abc/def')._path_ends_with_slash() is False

    def test_path_has_chunk_that_looks_like_year(self):
        assert URLFeatureExtractor('http://example.com/a')._path_has_chunk_that_looks_like_year() is False

        assert URLFeatureExtractor('http://example.com/2019/')._path_has_chunk_that_looks_like_year() is True
        assert URLFeatureExtractor('http://example.com/2019-xyz/')._path_has_chunk_that_looks_like_year() is True

        assert URLFeatureExtractor('http://example.com/3000/')._path_has_chunk_that_looks_like_year() is False
        assert URLFeatureExtractor('http://example.com/3000-xyz/')._path_has_chunk_that_looks_like_year() is False

    def test_path_has_chunk_that_looks_like_month(self):
        assert URLFeatureExtractor('http://example.com/a')._path_has_chunk_that_looks_like_month() is False

        assert URLFeatureExtractor('http://example.com/02/')._path_has_chunk_that_looks_like_month() is True
        assert URLFeatureExtractor('http://example.com/02-xyz/')._path_has_chunk_that_looks_like_month() is True
        assert URLFeatureExtractor('http://example.com/2/')._path_has_chunk_that_looks_like_month() is True
        assert URLFeatureExtractor('http://example.com/2-xyz/')._path_has_chunk_that_looks_like_month() is True

        assert URLFeatureExtractor('http://example.com/13/')._path_has_chunk_that_looks_like_month() is False
        assert URLFeatureExtractor('http://example.com/13-xyz/')._path_has_chunk_that_looks_like_month() is False

    def test_path_has_chunk_that_looks_like_day(self):
        assert URLFeatureExtractor('http://example.com/a')._path_has_chunk_that_looks_like_day() is False

        assert URLFeatureExtractor('http://example.com/02/')._path_has_chunk_that_looks_like_day() is True
        assert URLFeatureExtractor('http://example.com/02-xyz/')._path_has_chunk_that_looks_like_day() is True
        assert URLFeatureExtractor('http://example.com/2/')._path_has_chunk_that_looks_like_day() is True
        assert URLFeatureExtractor('http://example.com/2-xyz/')._path_has_chunk_that_looks_like_day() is True

        assert URLFeatureExtractor('http://example.com/32/')._path_has_chunk_that_looks_like_day() is False
        assert URLFeatureExtractor('http://example.com/32-xyz/')._path_has_chunk_that_looks_like_day() is False

    def test_path_length(self):
        assert URLFeatureExtractor('http://example.com')._path_length() == 0
        assert URLFeatureExtractor('http://example.com/')._path_length() == 0
        assert URLFeatureExtractor('http://example.com///')._path_length() == 0

        assert URLFeatureExtractor('http://example.com///a')._path_length() == 1
        assert URLFeatureExtractor('http://example.com///a/')._path_length() == 1
        assert URLFeatureExtractor('http://example.com///a//')._path_length() == 1

        assert URLFeatureExtractor('http://example.com///a//b/')._path_length() == 3
        assert URLFeatureExtractor('http://example.com///a//b/?c=d')._path_length() == 3

        assert URLFeatureExtractor('http://example.com/super-long-part/a/')._longest_path_part_from_end_index() == 1
        assert URLFeatureExtractor('http://example.com/a/super-long-part/')._longest_path_part_from_end_index() == 0
