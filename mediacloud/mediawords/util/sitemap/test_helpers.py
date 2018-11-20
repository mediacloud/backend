import datetime

from mediawords.util.sitemap.helpers import html_unescape_ignore_none, parse_sitemap_publication_date


def test_html_unescape_ignore_none():
    assert html_unescape_ignore_none("test &amp; test") == "test & test"
    assert html_unescape_ignore_none(None) is None


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
