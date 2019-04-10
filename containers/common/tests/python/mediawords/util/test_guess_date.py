#!/usr/bin/env py.test

import pytest

from mediawords.util.guess_date import guess_date, McGuessDateException


def test_guess_date():
    with pytest.raises(McGuessDateException):
        # noinspection PyTypeChecker
        guess_date(url=None, html=None)
        # noinspection PyTypeChecker
        guess_date(url="https://www.nytimes.com/2017/10/some_news.html", html=None)
        # noinspection PyTypeChecker
        guess_date(url=None, html="Something")

    # Found
    result = guess_date(
        url="https://www.nytimes.com/2017/10/some_news.html",
        html="""
            <html><head>
            <meta property="article:published" itemprop="datePublished" content="2017-10-13T04:56:54-04:00" />
            </head></html>
        """)
    assert result.found is True
    assert result.guess_method.startswith('Extracted from')
    assert result.timestamp == 1507885014
    assert result.date == '2017-10-13T08:56:54'

    # Not found (undateable, even though the date is there in <meta />)
    result = guess_date(
        url="https://en.wikipedia.org/wiki/Progressive_tax",
        html="""
            <html><head>
            <meta property="article:published" itemprop="datePublished" content="2017-10-13T04:56:54-04:00" />
            </head></html>
        """)
    assert result.found is False
    assert result.guess_method is None
    assert result.timestamp is None
    assert result.date is None
