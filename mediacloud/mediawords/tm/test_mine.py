from mediawords.test.test_database import TestDatabaseTestCase
from mediawords.tm.mine import postgres_regex_match


class TestTMMine(TestDatabaseTestCase):
    def test_postgres_regex_match(self):
        regex = '(?: [[:<:]]alt-right | [[:<:]]alt[[:space:]]+right | [[:<:]]alternative[[:space:]]+right )'

        # Match
        strings = ['This is a string describing alt-right and something else.']
        assert postgres_regex_match(db=self.db(), strings=strings, regex=regex) is True

        # No match
        strings = ['This is a string describing just something else.']
        assert postgres_regex_match(db=self.db(), strings=strings, regex=regex) is False

        # One matching string
        strings = [
            'This is a string describing something else.',
            'This is a string describing alt-right.',
        ]
        assert postgres_regex_match(db=self.db(), strings=strings, regex=regex) is True

        # Two non-matching strings
        strings = [
            'This is a string describing something else.',
            'This is a string describing something else again.',
        ]
        assert postgres_regex_match(db=self.db(), strings=strings, regex=regex) is False

        # String over 1 MB
        strings = [
            'alt-right alt-right ' * (1024 * 1024)
        ]
        assert postgres_regex_match(db=self.db(), strings=strings, regex=regex) is True

        # String where regex is not in the first 1 MB
        strings = [
            'a' * (1024 * 1024 + 10) + ' alt-right alt-right'
        ]
        assert postgres_regex_match(db=self.db(), strings=strings, regex=regex) is False

        # String with a null char
        strings = [
            "alt-right alt-right \x00 alt-right"
        ]
        assert postgres_regex_match(db=self.db(), strings=strings, regex=regex) is False
