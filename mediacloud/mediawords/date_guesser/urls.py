import datetime
import itertools
import re

import arrow
import pytz

from .constants import LOCALE, Accuracy, Guess, GuessMethod


# inspired by (MIT licensed) https://github.com/codelucas/newspaper
_LOCALE = arrow.locales.get_locale(LOCALE)
SEPARATOR = r'([\./\-_]{0,1})'
YEAR_PATTERN = r'(?P<year>(?:19|20)\d{2})'
MONTH_PATTERN = r'(?P<month>(?:[0-3]{0,1}[0-9])|(?:[a-zA-Z]{3,5}))'
DAY_PATTERN = r'(?P<day>[0-3]{0,1}[0-9])'

URL_DATE_REGEX = re.compile(
    r'{sep}{year}{sep}{month}{sep}(?:{day}{sep})?(?!\d)'.format(
        sep=SEPARATOR, year=YEAR_PATTERN, month=MONTH_PATTERN, day=DAY_PATTERN))

URL_DATE_REGEX_BACKWARDS = re.compile(
    r'{sep}{month}(?:{sep}{day})?{sep}{year}{sep}(?!\d)'.format(
        sep=SEPARATOR, year=YEAR_PATTERN, month=MONTH_PATTERN, day=DAY_PATTERN))


def url_date_generator(url):
    """Generates possible date matches from a url

    Parameters
    ----------
    url: string

    Yields
    ------
    dict
        dictionary with keys 'year', 'month', 'day'
    """
    matches = itertools.chain(URL_DATE_REGEX.finditer(url), URL_DATE_REGEX_BACKWARDS.finditer(url))
    for match in matches:
        yield match.groupdict()


def parse_url_for_date(url):
    """Extracts a date from the url"""
    accuracy = Accuracy.NONE
    for captures in url_date_generator(url):
        captures['year'] = int(captures['year'])
        if captures['year'] < 1990 or captures['year'] > 2030:
            continue
        try:
            captures['month'] = int(captures['month'])
        except ValueError:  # month is a string
            month = captures['month'].title()
            manual_months = {
                'Sept': 9
            }
            if month in _LOCALE.month_abbreviations:
                captures['month'] = _LOCALE.month_abbreviations.index(month)
            elif month in manual_months:
                captures['month'] = manual_months[month]
            else:
                continue

        if captures['day'] is None:
            captures['day'] = 15
            accuracy = Accuracy.PARTIAL
        else:
            captures['day'] = int(captures['day'])
            accuracy = Accuracy.DATE

        try:
            date_guess = datetime.datetime(tzinfo=pytz.utc, **captures)
            return Guess(date_guess, accuracy, GuessMethod.URL)
        except ValueError:
            pass
    return Guess(None, Accuracy.NONE, GuessMethod.NONE)
