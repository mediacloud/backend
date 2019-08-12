from unittest import TestCase

from mediawords.util.sitemap.url_vectors import URLFeatureExtractor


class TestURLFeatureExtractor(TestCase):

    def test_is_dec_hex_number(self):
        # noinspection PyTypeChecker
        assert URLFeatureExtractor._is_dec_hex_number(None) is False
        assert URLFeatureExtractor._is_dec_hex_number('') is False

        # Decimal
        assert URLFeatureExtractor._is_dec_hex_number('3') is True
        assert URLFeatureExtractor._is_dec_hex_number('30000') is True
        assert URLFeatureExtractor._is_dec_hex_number('0') is True

        # Hexadecimal
        assert URLFeatureExtractor._is_dec_hex_number('00ff') is True
        assert URLFeatureExtractor._is_dec_hex_number('0123456789abcdef') is True
        assert URLFeatureExtractor._is_dec_hex_number('ABCDEF0123456789') is True

        # Neither
        assert URLFeatureExtractor._is_dec_hex_number('duckling') is False

    def test_query_string_keys_count(self):
        assert URLFeatureExtractor('http://example.com/abc')._query_string_keys_count() == 0
        assert URLFeatureExtractor('http://example.com/abc?')._query_string_keys_count() == 0

        assert URLFeatureExtractor('http://example.com/abc?a')._query_string_keys_count() == 1
        assert URLFeatureExtractor('http://example.com/abc?a=')._query_string_keys_count() == 1
        assert URLFeatureExtractor('http://example.com/abc?a=b')._query_string_keys_count() == 1
        assert URLFeatureExtractor('http://example.com/abc?a=b&')._query_string_keys_count() == 1

        assert URLFeatureExtractor('http://example.com/abc?a=b&c')._query_string_keys_count() == 2
        assert URLFeatureExtractor('http://example.com/abc?a=b&c=')._query_string_keys_count() == 2
        assert URLFeatureExtractor('http://example.com/abc?a=b&c=d')._query_string_keys_count() == 2
        assert URLFeatureExtractor('http://example.com/abc?a=b&c=d&c=d')._query_string_keys_count() == 2

    def test_query_string_keys_include_a_number(self):
        assert URLFeatureExtractor('http://example.com')._query_string_keys_include_a_number() is False
        assert URLFeatureExtractor('http://example.com/?')._query_string_keys_include_a_number() is False

        assert URLFeatureExtractor('http://example.com/?a')._query_string_keys_include_a_number() is True
        assert URLFeatureExtractor('http://example.com/?a=')._query_string_keys_include_a_number() is True
        assert URLFeatureExtractor('http://example.com/?a=xxx')._query_string_keys_include_a_number() is True

        assert URLFeatureExtractor('http://example.com/?a=123')._query_string_keys_include_a_number() is True
        assert URLFeatureExtractor('http://example.com/?a=abc')._query_string_keys_include_a_number() is True

        assert URLFeatureExtractor('http://example.com/?a=123&b=xyz')._query_string_keys_include_a_number() is True
        assert URLFeatureExtractor('http://example.com/?a=abc&b=xyz')._query_string_keys_include_a_number() is True

    def test_query_string_values_include_a_number(self):
        assert URLFeatureExtractor('http://example.com')._query_string_values_include_a_number() is False
        assert URLFeatureExtractor('http://example.com/?')._query_string_values_include_a_number() is False
        assert URLFeatureExtractor('http://example.com/?a')._query_string_values_include_a_number() is False
        assert URLFeatureExtractor('http://example.com/?a=')._query_string_values_include_a_number() is False
        assert URLFeatureExtractor('http://example.com/?a=xxx')._query_string_values_include_a_number() is False

        assert URLFeatureExtractor('http://example.com/?a=123')._query_string_values_include_a_number() is True
        assert URLFeatureExtractor('http://example.com/?a=abc')._query_string_values_include_a_number() is True

        assert URLFeatureExtractor('http://example.com/?a=123&b=xyz')._query_string_values_include_a_number() is True
        assert URLFeatureExtractor('http://example.com/?a=abc&b=xyz')._query_string_values_include_a_number() is True

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

    def test_path_ends_with_number(self):
        assert URLFeatureExtractor('http://example.com')._path_ends_with_number() is False
        assert URLFeatureExtractor('http://example.html')._path_ends_with_number() is False
        assert URLFeatureExtractor('http://example.com/')._path_ends_with_number() is False
        assert URLFeatureExtractor('http://example.com/test')._path_ends_with_number() is False
        assert URLFeatureExtractor('http://example.com/test.html')._path_ends_with_number() is False
        assert URLFeatureExtractor('http://example.com/.html')._path_ends_with_number() is False

        assert URLFeatureExtractor('http://example.com/012')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/abc')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/012.html')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/abc.html')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/012/012')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/abc/abc')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/012/012.html')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/abc/abc.html')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/badger/badger-012.html')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/badger/badger-abc.html')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/badger/badger-012')._path_ends_with_number() is True
        assert URLFeatureExtractor('http://example.com/badger/badger-abc')._path_ends_with_number() is True

    def test_path_ends_with_slash(self):
        assert URLFeatureExtractor('http://example.com')._path_ends_with_slash() is True
        assert URLFeatureExtractor('http://example.com/')._path_ends_with_slash() is True
        assert URLFeatureExtractor('http://example.com/abc/')._path_ends_with_slash() is True
        assert URLFeatureExtractor('http://example.com/abc/def/')._path_ends_with_slash() is True

        assert URLFeatureExtractor('http://example.com/abc/def')._path_ends_with_slash() is False

    def test_path_parts_count(self):
        assert URLFeatureExtractor('http://example.com')._path_parts_count() == 0
        assert URLFeatureExtractor('http://example.com/')._path_parts_count() == 0
        assert URLFeatureExtractor('http://example.com///')._path_parts_count() == 0
        assert URLFeatureExtractor('http://example.com///?a=b&c=d')._path_parts_count() == 0

        assert URLFeatureExtractor('http://example.com/a')._path_parts_count() == 1
        assert URLFeatureExtractor('http://example.com/aa')._path_parts_count() == 1
        assert URLFeatureExtractor('http://example.com/aa/')._path_parts_count() == 1
        assert URLFeatureExtractor('http://example.com/aa///')._path_parts_count() == 1
        assert URLFeatureExtractor('http://example.com//aa///')._path_parts_count() == 1

        assert URLFeatureExtractor('http://example.com/aa/bb')._path_parts_count() == 2

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

    def test_longest_path_part_length(self):
        assert URLFeatureExtractor('http://example.com')._longest_path_part_length() == 0
        assert URLFeatureExtractor('http://example.com/')._longest_path_part_length() == 0
        assert URLFeatureExtractor('http://example.com///')._longest_path_part_length() == 0

        assert URLFeatureExtractor('http://example.com/a')._longest_path_part_length() == 1
        assert URLFeatureExtractor('http://example.com/a/b')._longest_path_part_length() == 1

        assert URLFeatureExtractor('http://example.com/a/bb')._longest_path_part_length() == 2

    def test_longest_path_part_from_start_index(self):
        assert URLFeatureExtractor('http://example.com')._longest_path_part_from_start_index() == 0
        assert URLFeatureExtractor('http://example.com/')._longest_path_part_from_start_index() == 0
        assert URLFeatureExtractor('http://example.com/a')._longest_path_part_from_start_index() == 0
        assert URLFeatureExtractor('http://example.com/a/')._longest_path_part_from_start_index() == 0

        assert URLFeatureExtractor('http://example.com/super-long-part/a/')._longest_path_part_from_start_index() == 0
        assert URLFeatureExtractor('http://example.com/a/super-long-part/')._longest_path_part_from_start_index() == 1

    def test_longest_path_part_from_end_index(self):
        assert URLFeatureExtractor('http://example.com')._longest_path_part_from_end_index() == 0
        assert URLFeatureExtractor('http://example.com/')._longest_path_part_from_end_index() == 0
        assert URLFeatureExtractor('http://example.com/a')._longest_path_part_from_end_index() == 0
        assert URLFeatureExtractor('http://example.com/a/')._longest_path_part_from_end_index() == 0

        assert URLFeatureExtractor('http://example.com/super-long-part/a/')._longest_path_part_from_end_index() == 1
        assert URLFeatureExtractor('http://example.com/a/super-long-part/')._longest_path_part_from_end_index() == 0

    def test_consecutive_number_only_path_part_count(self):
        assert URLFeatureExtractor('http://example.com')._consecutive_number_only_path_part_count() == 0
        assert URLFeatureExtractor('http://example.com/')._consecutive_number_only_path_part_count() == 0
        assert URLFeatureExtractor('http://example.com/x')._consecutive_number_only_path_part_count() == 0
        assert URLFeatureExtractor('http://example.com/x/')._consecutive_number_only_path_part_count() == 0
        assert URLFeatureExtractor('http://example.com/x/y/z/')._consecutive_number_only_path_part_count() == 0

        assert URLFeatureExtractor('http://example.com/a')._consecutive_number_only_path_part_count() == 1
        assert URLFeatureExtractor('http://example.com/a/')._consecutive_number_only_path_part_count() == 1
        assert URLFeatureExtractor('http://example.com/a///')._consecutive_number_only_path_part_count() == 1
        assert URLFeatureExtractor('http://example.com/1')._consecutive_number_only_path_part_count() == 1
        assert URLFeatureExtractor('http://example.com/1///')._consecutive_number_only_path_part_count() == 1

        assert URLFeatureExtractor('http://example.com/a/b/123/')._consecutive_number_only_path_part_count() == 3
        assert URLFeatureExtractor('http://example.com/a/b/123///')._consecutive_number_only_path_part_count() == 3
        assert URLFeatureExtractor('http://example.com/1/2/3/')._consecutive_number_only_path_part_count() == 3
        assert URLFeatureExtractor('http://example.com/1/2/3///')._consecutive_number_only_path_part_count() == 3

        assert URLFeatureExtractor(
            'http://example.com/2019/03/03/hello/'
        )._consecutive_number_only_path_part_count() == 3

        assert URLFeatureExtractor(
            'http://example.com/2019/hello/03/03/hello/'
        )._consecutive_number_only_path_part_count() == 2

    def test_number_only_path_part_chunk_count(self):
        assert URLFeatureExtractor('http://example.com')._number_only_path_part_chunk_count() == 0
        assert URLFeatureExtractor('http://example.com/')._number_only_path_part_chunk_count() == 0
        assert URLFeatureExtractor('http://example.com/x')._number_only_path_part_chunk_count() == 0
        assert URLFeatureExtractor('http://example.com/x/')._number_only_path_part_chunk_count() == 0
        assert URLFeatureExtractor('http://example.com/x/y/z/')._number_only_path_part_chunk_count() == 0

        assert URLFeatureExtractor('http://example.com/a')._number_only_path_part_chunk_count() == 1
        assert URLFeatureExtractor('http://example.com/a/')._number_only_path_part_chunk_count() == 1

        assert URLFeatureExtractor('http://example.com/2019/03/03/hello/')._number_only_path_part_chunk_count() == 3
        assert URLFeatureExtractor(
            'http://example.com/2019/hello/03/03/hello/'
        )._number_only_path_part_chunk_count() == 3

        assert URLFeatureExtractor('http://example.com/2019-x-03-y-01-z/')._number_only_path_part_chunk_count() == 3

    def test_first_path_part_with_number_chunk_from_start_index(self):
        assert URLFeatureExtractor('http://example.com')._first_path_part_with_number_chunk_from_start_index() == -1
        assert URLFeatureExtractor('http://example.com/')._first_path_part_with_number_chunk_from_start_index() == -1
        assert URLFeatureExtractor('http://example.com/x')._first_path_part_with_number_chunk_from_start_index() == -1
        assert URLFeatureExtractor('http://example.com/x/')._first_path_part_with_number_chunk_from_start_index() == -1
        assert URLFeatureExtractor(
            'http://example.com/x/y/z/'
        )._first_path_part_with_number_chunk_from_start_index() == -1

        assert URLFeatureExtractor('http://example.com/a')._first_path_part_with_number_chunk_from_start_index() == 0
        assert URLFeatureExtractor('http://example.com/a/')._first_path_part_with_number_chunk_from_start_index() == 0
        assert URLFeatureExtractor('http://example.com/123')._first_path_part_with_number_chunk_from_start_index() == 0
        assert URLFeatureExtractor('http://example.com/123/')._first_path_part_with_number_chunk_from_start_index() == 0

        assert URLFeatureExtractor(
            'http://example.com/xxx/a'
        )._first_path_part_with_number_chunk_from_start_index() == 1
        assert URLFeatureExtractor(
            'http://example.com/xxx/a/'
        )._first_path_part_with_number_chunk_from_start_index() == 1
        assert URLFeatureExtractor(
            'http://example.com/xxx/123'
        )._first_path_part_with_number_chunk_from_start_index() == 1
        assert URLFeatureExtractor(
            'http://example.com/xxx/123/'
        )._first_path_part_with_number_chunk_from_start_index() == 1

        assert URLFeatureExtractor(
            'http://example.com/xxx/foobarbaz-a'
        )._first_path_part_with_number_chunk_from_start_index() == 1
        assert URLFeatureExtractor(
            'http://example.com/xxx/foobarbaz-a/'
        )._first_path_part_with_number_chunk_from_start_index() == 1
        assert URLFeatureExtractor(
            'http://example.com/xxx/foobarbaz-123'
        )._first_path_part_with_number_chunk_from_start_index() == 1
        assert URLFeatureExtractor(
            'http://example.com/xxx/foobarbaz-123/'
        )._first_path_part_with_number_chunk_from_start_index() == 1

    def test_last_path_part_with_number_chunk_from_end_index(self):
        assert URLFeatureExtractor('http://example.com')._last_path_part_with_number_chunk_from_end_index() == -1
        assert URLFeatureExtractor('http://example.com/')._last_path_part_with_number_chunk_from_end_index() == -1
        assert URLFeatureExtractor('http://example.com/x')._last_path_part_with_number_chunk_from_end_index() == -1
        assert URLFeatureExtractor('http://example.com/x/')._last_path_part_with_number_chunk_from_end_index() == -1
        assert URLFeatureExtractor('http://example.com/x/y/z/')._last_path_part_with_number_chunk_from_end_index() == -1

        assert URLFeatureExtractor('http://example.com/a')._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor('http://example.com/a/')._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor('http://example.com/123')._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor('http://example.com/123/')._last_path_part_with_number_chunk_from_end_index() == 0

        assert URLFeatureExtractor('http://example.com/xxx/a')._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor('http://example.com/xxx/a/')._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor('http://example.com/xxx/123')._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor(
            'http://example.com/xxx/123/')._last_path_part_with_number_chunk_from_end_index() == 0

        assert URLFeatureExtractor(
            'http://example.com/xxx/foobarbaz-a'
        )._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor(
            'http://example.com/xxx/foobarbaz-a/'
        )._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor(
            'http://example.com/xxx/foobarbaz-123'
        )._last_path_part_with_number_chunk_from_end_index() == 0
        assert URLFeatureExtractor(
            'http://example.com/xxx/foobarbaz-123/'
        )._last_path_part_with_number_chunk_from_end_index() == 0
