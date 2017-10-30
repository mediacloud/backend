import datetime
import itertools
import re
from urllib.parse import urlparse

import arrow
import pytz

from .constants import LOCALE, Accuracy, Guess, NO_METHOD


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
    (dict, str)
        dictionary with keys 'year', 'month', 'day'
        string describing how the dictionary was found
    """
    matches = itertools.chain(URL_DATE_REGEX.finditer(url), URL_DATE_REGEX_BACKWARDS.finditer(url))
    for match in matches:
        method = 'Found {} in url'.format(match.group())
        yield match.groupdict(), method


def parse_url_for_date(url):
    """Extracts a date from the url

    Parameters
    ----------
    url: string

    Returns
    -------
    mediawords.date_guesser.constants.Guess
    """
    accuracy = Accuracy.NONE
    for captures, method in url_date_generator(url):
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
            return Guess(date_guess, accuracy, method)
        except ValueError:
            pass
    return Guess(None, Accuracy.NONE, NO_METHOD)


def filter_url_for_undateable(url):
    """Common sense checks for a page not having a date.

    Reasons for this include being a non-static page or being a login page.
    Common examples are wikipedia, or a nytimes topics page.

    Parameters
    ----------
    url: string

    Returns
    -------
    mediawords.date_guesser.constants.Guess or None
        guess describing why the page is undateable or None if it might be dateable
    """
    parsed = urlparse(url)
	# url fragments that are likely to be undateable
    invalid_paths = {
        'search',
        'tag',
    }
    path_parts = set(parsed.path.strip('/').split('/'))

    hostname = parsed.hostname
    if hostname is None:
        return Guess(None, Accuracy.NONE, 'Invalid url ({})'.format(url[:200]))

    elif hostname.endswith('wikipedia.org'):
        return Guess(None, Accuracy.NONE, 'No date for wiki pages')

    elif hostname.endswith('twitter.com') and ('status' not in path_parts):
        return Guess(None, Accuracy.NONE, 'Twitter, but not a single tweet')

    elif parsed.path.strip('/') == '':
        return Guess(None, Accuracy.NONE,
                    'Empty `path`, might be frontpage of {}'.format(hostname))
    path_contains = invalid_paths.intersection(path_parts)
    if path_contains:  # nonempty intersection is truthy
        bad_parts = ', '.join(['"{}"' for segment in path_contains])
        return Guess(None, Accuracy.NONE, 'URL ({}) contains {}'.format(url, bad_parts) )

    return None
