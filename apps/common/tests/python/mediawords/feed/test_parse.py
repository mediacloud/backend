import re

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


def test_rss_enclosure():
    rss_feed = """
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
xmlns:content="http://purl.org/rss/1.0/modules/content/"
xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
    <channel>
        <title>Channel title</title>
        <lastBuildDate>Tue, 04 Feb 2020 16:01:20 -0500</lastBuildDate>
        <link>https://www.example.com/</link>
        <language>en</language>
        <copyright>&#x2117; &amp; &#xA9; 2020 Channel copyright</copyright>
        <itunes:subtitle><![CDATA[Channel description]]></itunes:subtitle>
        <itunes:author>Channel author</itunes:author>
        <itunes:summary><![CDATA[Channel summary]]></itunes:summary>
        <itunes:type>episodic</itunes:type>
        <itunes:explicit>false</itunes:explicit>
        <description><![CDATA[Channel description]]></description>
        <itunes:owner>
            <itunes:name>Channel author</itunes:name>
            <itunes:email>example@example.com</itunes:email>
        </itunes:owner>
        <image>
            <url>https://www.example.com/image.jpg</url>
            <title>Channel title</title>
            <link>https://www.example.com/</link>
        </image>
        <itunes:image href="https://www.example.com/image.jpg" />
        <itunes:category text="Comedy" />
        
        <item>
            <itunes:title>Item iTunes title</itunes:title>
            <title>Item title</title>
            <description><![CDATA[<p>Item description</p>]]></description>
            <link><![CDATA[http://www.example.com/item]]></link>
            <content:encoded><![CDATA[<p>Item description</p>]]></content:encoded>
            <itunes:author>Item author</itunes:author>
            <itunes:summary></itunes:summary>
            <enclosure url="https://www.example.com/item.mp3" length="123456789" type="audio/mpeg" />
            <guid isPermaLink="false">example.com-item</guid>
            <pubDate>Sat, 01 Feb 2020 10:00:00 -0500</pubDate>
            <itunes:duration>4479</itunes:duration>
            <itunes:keywords></itunes:keywords>
            <itunes:season></itunes:season>
            <itunes:episode></itunes:episode>
            <itunes:episodeType>full</itunes:episodeType>
            <itunes:explicit>false</itunes:explicit>
        </item>
    </channel>
</rss>
    """

    feed = parse_feed(rss_feed)
    assert feed, "Feed was parsed."

    assert len(feed.items()) == 1, "Exactly one item has to be found."
    item = feed.items()[0]

    assert len(item.enclosures()) == 1, "Exactly one enclosure has to be found."
    enclosure = item.enclosures()[0]

    assert enclosure.url() == "https://www.example.com/item.mp3"
    assert enclosure.length() == 123456789
    assert enclosure.mime_type() == "audio/mpeg"


def test_atom_enclosures():
    atom_feed = """
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
    <title>Channel title</title>
    <updated>2003-12-13T18:30:02Z</updated>
    <link href="https://www.example.com/" />
    <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
    <author>
        <name>Item author</name>
    </author>
  
    <entry>
        <title>Item title</title>
        <link href="http://www.example.com/item" />
        <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
        <summary>Item description</summary>
        <updated>2003-12-13T18:30:02Z</updated>
        
        <link rel="enclosure"
            type="audio/mpeg"
            title="MP3 file"
            href="https://www.example.com/item.mp3"
            length="123456789" />
        <link rel="enclosure"
            type="audio/mp4"
            title="M4A file"
            href="https://www.example.com/item.m4a"
            length="234567890" />

    </entry>

</feed>
    """

    feed = parse_feed(atom_feed)
    assert feed, "Feed was parsed."

    assert len(feed.items()) == 1, "Exactly one item has to be found."
    item = feed.items()[0]

    assert len(item.enclosures()) == 2, "Two enclosures have to be found."

    enclosure_1 = item.enclosures()[0]
    assert enclosure_1.url() == "https://www.example.com/item.mp3"
    assert enclosure_1.length() == 123456789
    assert enclosure_1.mime_type() == "audio/mpeg"

    enclosure_2 = item.enclosures()[1]
    assert enclosure_2.url() == "https://www.example.com/item.m4a"
    assert enclosure_2.length() == 234567890
    assert enclosure_2.mime_type() == "audio/mp4"
