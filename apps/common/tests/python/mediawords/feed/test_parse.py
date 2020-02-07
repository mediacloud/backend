import re

from dateutil.parser import parse as parse_date

from mediawords.feed.parse import parse_feed


def test_invalid_feeds():
    # noinspection PyTypeChecker
    assert parse_feed(None) is None, "Parsing None should have returned None."
    assert parse_feed('') is None, "Parsing empty string should have returned None."
    assert parse_feed('   ') is None, "Parsing whitespace should have returned None."

    assert parse_feed("""
        <html>
        <head>
            <title>Acme News</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
        </head>
        <body>
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                This page is totally not a valid RSS / Atom feed.
            </p>
        </body>
        </html>
    """) is None, "Parsing HTML should have returned None."


def test_empty_feed():
    feed_text = """
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet href="/css/rss20.xsl" type="text/xsl"?>
<rss version="2.0">
    <channel>
        <title>foo</title>
        <link>http://example.com</link>
        <description/>
        <language>en</language>
        <item xmlns:atom="http://www.w3.org/2005/Atom">
            <title><![CDATA[]]></title>
            <link/>
            <guid isPermaLink="false"/>
            <pubDate></pubDate>
        </item>
    </channel>
</rss>
    """

    feed = parse_feed(feed_text)
    assert feed, "Feed was parsed."

    for item in feed.items():
        assert item.title() == "", "Title is an empty string."
        assert item.link() is None, "URL is None."  # due to fallback on GUID which is also unset
        assert item.guid() == "", "GUID is an empty string."
        assert item.guid_if_valid() is None, "Valid GUID is None."
        assert item.publish_date() is None, "Publish date is None."
        assert item.publish_date_sql() is None, "Publish date SQL is None."


def test_undocumented_canonical_url_tag():
    feed_text = """
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet href="/css/rss20.xsl" type="text/xsl"?>
<rss version="2.0" xmlns:whatever="http://example.com/whatever/">
    <channel>
        <title>foo</title>
        <link>http://example.com</link>
        <description/>
        <language>en</language>
        <item xmlns:atom="http://www.w3.org/2005/Atom">
            <title><![CDATA[]]></title>
            <link/>
            <guid isPermaLink="false"/>
            <pubDate></pubDate>
            <whatever:canonical_url>http://www.example.com/item.html</whatever:canonical_url>
        </item>
    </channel>
</rss>
    """

    feed = parse_feed(feed_text)
    assert feed, "Feed was parsed."

    for item in feed.items():
        assert item.link() == "http://www.example.com/item.html", "URL is set."


def _test_feed_contents(feed_contents: str) -> None:
    feed = parse_feed(feed_contents)
    assert feed, "Feed was parsed."

    assert feed.title() == 'Test feed', "Feed title is set."
    assert len(feed.items()) == 2, "Feed has two items."

    first_item = feed.items()[0]

    assert first_item.title() == 'First item', "First item title."
    assert first_item.link() == 'http://www.example.com/first_item.html', "First item link."
    assert first_item.publish_date() == '2016-12-14T04:04:01Z', "First item publish date."

    # publish_date_sql() is dependent on machine's timezone (which shouldn't be the case, but it is)
    assert re.search(r'^2016-12-1\d \d\d:\d\d:\d\d$', first_item.publish_date_sql()), "First item SQL publish date."

    assert first_item.guid() == 'http://www.example.com/first_item.html', "First item GUID."
    assert first_item.guid_if_valid() == 'http://www.example.com/first_item.html', "First item valid GUID."
    assert first_item.description() == 'This is a first item.', "First item description."

    second_item = feed.items()[1]

    assert second_item.title() == 'ɯǝʇı puoɔǝS', "Second item title."
    assert second_item.link() == 'http://www.example.com/second_item.html', "Second item link."
    assert second_item.publish_date() == '2016-12-14T04:05:01Z', "Second item publish date."

    # publish_date_sql() is dependent on machine's timezone (which shouldn't be the case, but it is)
    assert re.search(r'^2016-12-1\d \d\d:\d\d:\d\d$', second_item.publish_date_sql()), "Second item SQL publish date."

    assert second_item.guid() == 'http://www.example.com/second_item.html', "Second item GUID."
    assert second_item.guid_if_valid() == 'http://www.example.com/second_item.html', "Second item valid GUID."
    assert second_item.description() == '<strong>This is a second item.</strong>', "Second item description with HTML."


def test_rss_feed():
    rss_feed = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
    <channel>
        <title>Test feed</title>
        <link>http://www.example.com/</link>
        <description>This is a test feed.</description>
        <lastBuildDate>Wed, 14 Dec 2016 04:00:00 GMT</lastBuildDate>
        <item>
            <title>First item</title>
            <author>foobar@example.com</author>
            <link>http://www.example.com/first_item.html</link>
            <pubDate>Wed, 14 Dec 2016 04:04:01 GMT</pubDate>
            <guid isPermaLink="true">http://www.example.com/first_item.html</guid>
            <description>This is a first item.</description>
        </item>
        <item>
            <title>ɯǝʇı puoɔǝS</title>  <!-- UTF-8 test -->
            <author>foobar@example.com</author>
            <link>http://www.example.com/second_item.html</link>
            <pubDate>Wed, 14 Dec 2016 04:05:01 GMT</pubDate>
            <guid isPermaLink="false">http://www.example.com/second_item.html</guid>   <!-- Even though it is a link -->
            
            <!-- Instead of description: -->
            <content:encoded><![CDATA[<strong>This is a second item.</strong>]]></content:encoded>
        </item>
    </channel>
</rss>
    """

    _test_feed_contents(rss_feed)


def test_atom_feed():
    atom_feed = """
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">

    <title>Test feed</title>
    <subtitle>This is a test feed.</subtitle>
    <link href="http://www.example.com/"/>
    <updated>2016-12-14T04:00:00Z</updated>
    <id>http://www.example.com/</id>
    <entry>
        <title>First item</title>
        <link href="http://www.example.com/first_item.html" />
        <id>http://www.example.com/first_item.html</id>
        <author>
            <name>Foo Bar</name>
        </author>
        <updated>2016-12-14T04:04:01Z</updated>
        <summary>This is a first item.</summary>
    </entry>
    <entry>
        <title>ɯǝʇı puoɔǝS</title>  <!-- UTF-8 test -->
        <link href="http://www.example.com/second_item.html" />
        <id>http://www.example.com/second_item.html</id>
        <author>
            <name>Foo Bar</name>
        </author>
        <updated>2016-12-14T04:05:01Z</updated>
        <summary><![CDATA[<strong>This is a second item.</strong>]]></summary>
    </entry>
</feed>
    """
    _test_feed_contents(atom_feed)


def test_rdf_feed():
    rdf_feed = """
<?xml version="1.0" encoding="UTF-8"?>

<rdf:RDF
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns="http://purl.org/rss/1.0/"
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">

    <channel rdf:about="http://www.example.com/about">
        <title>Test feed</title>
        <link>http://www.example.com/</link>
        <description>This is a test feed.</description>
        <items xmlns="http://apache.org/cocoon/i18n/2.1">
            <rdf:Seq>
                <rdf:li rdf:resource="http://www.example.com/first_item.html"/>
                <rdf:li rdf:resource="http://www.example.com/second_item.html"/>
            </rdf:Seq>
        </items>
        <dc:date>2016-12-14T04:00:00Z</dc:date>
    </channel>

    <item rdf:about="http://www.example.com/first_item.html">
        <title>First item</title>
        <link>http://www.example.com/first_item.html</link>
        <description>This is a first item.</description>
        <dc:date>2016-12-14T04:04:01Z</dc:date>
    </item>
    <item rdf:about="http://www.example.com/second_item.html">
        <title>ɯǝʇı puoɔǝS</title>
        <link>http://www.example.com/second_item.html</link>
        <description><![CDATA[<strong>This is a second item.</strong>]]></description>
        <dc:date>2016-12-14T04:05:01Z</dc:date>
    </item>

</rdf:RDF>
    """
    _test_feed_contents(rdf_feed)


def test_rss_weird_dates():
    weird_dates = [
        'Mon, 01 Jan 0001 00:00:00 +0100',
        '1875-09-17T00:00:00Z',
    ]

    at_least_one_valid_date_parsed = False

    for date in weird_dates:

        rss_feed = f"""
            <rss version="2.0">
                <channel>
                    <title>Weird dates</title>
                    <link>https://www.example.com/</link>
                    <description>Weird dates</description>
                    <item>
                        <title>Weird date</title>
                        <link>https://www.example.com/weird-date</link>
                        <description>Weird date</description>
                        <pubDate>{date}</pubDate>
                    </item>
                </channel>
            </rss>
        """

        feed = parse_feed(rss_feed)
        assert feed, "Feed was parsed."

        for item in feed.items():

            if item.publish_date():

                at_least_one_valid_date_parsed = True

                # Try parsing the date
                try:
                    parse_date(item.publish_date())
                except Exception as ex:
                    assert False, f"Unable to parse date {item.publish_date()}: {ex}"

                assert re.match(r'^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$', item.publish_date_sql())

    assert at_least_one_valid_date_parsed
