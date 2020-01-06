import re

from mediawords.feed.parse import parse_feed


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
    assert second_item.description() == 'This is a second item.', "Second item description."


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
            <content:encoded><![CDATA[This is a second item.]]></content:encoded>   <!-- Instead of description -->
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
        <summary><![CDATA[This is a second item.]]></summary>
    </entry>
</feed>
    """
    _test_feed_contents(atom_feed)
