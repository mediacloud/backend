#!/usr/bin/env py.test

import datetime

import pytz

from mediawords.util.sitemap.helpers import html_unescape_strip, parse_sitemap_publication_date


def test_html_unescape_strip():
    assert html_unescape_strip("  test &amp; test  ") == "test & test"
    assert html_unescape_strip(None) is None


def test_parse_sitemap_publication_date():
    assert parse_sitemap_publication_date("1997-07-16") == datetime.datetime(year=1997, month=7, day=16)
    assert parse_sitemap_publication_date("1997-07-16T19:20+01:00") == datetime.datetime(
        year=1997, month=7, day=16, hour=19, minute=20,
        tzinfo=datetime.timezone(datetime.timedelta(seconds=3600)),
    )
    assert parse_sitemap_publication_date("1997-07-16T19:20:30+01:00") == datetime.datetime(
        year=1997, month=7, day=16, hour=19, minute=20, second=30,
        tzinfo=datetime.timezone(datetime.timedelta(seconds=3600)),
    )
    assert parse_sitemap_publication_date("1997-07-16T19:20:30.45+01:00") == datetime.datetime(
        year=1997, month=7, day=16, hour=19, minute=20, second=30, microsecond=450000,
        tzinfo=datetime.timezone(datetime.timedelta(seconds=3600)),
    )

    # "Z" timezone instead of "+\d\d:\d\d"
    assert parse_sitemap_publication_date("2018-01-12T21:57:27Z") == datetime.datetime(
        year=2018, month=1, day=12, hour=21, minute=57, second=27, tzinfo=pytz.utc,
    )
