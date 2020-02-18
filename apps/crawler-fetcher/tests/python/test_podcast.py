from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_download_for_feed

from crawler_fetcher.handlers.feed_podcast import DownloadFeedPodcastHandler


def test_get_stories_from_podcast_feed():
    db = connect_to_db()

    test_feed_input = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:wfw="http://wellformedweb.org/CommentAPI/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:atom="http://www.w3.org/2005/Atom"
    xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"
    xmlns:slash="http://purl.org/rss/1.0/modules/slash/"
    xmlns:creativeCommons="http://backend.userland.com/creativeCommonsRssModule"
> 
    <channel>
        <title>David Larochelle&#039;s Blog</title>
        <atom:link
            href="http://blogs.law.harvard.edu/dlarochelle/feed/"
            rel="self"
            type="application/rss+xml" />
        <link>https://blogs.law.harvard.edu/dlarochelle</link>
        <description></description>
        <lastBuildDate>Mon, 09 Jan 2012 06:20:10 +0000</lastBuildDate>
        <language>en</language>
        <sy:updatePeriod>hourly</sy:updatePeriod>
        <sy:updateFrequency>1</sy:updateFrequency>
        <generator>http://wordpress.org/?v=3.2.1</generator>
        <creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>

        <item>
            <title></title>
            <link>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/</link>
            <comments>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/#comments</comments>
            <dc:creator>dlarochelle</dc:creator>
            <category><![CDATA[Uncategorized]]></category>
            <guid isPermaLink="false">http://blogs.law.harvard.edu/dlarochelle/?p=350</guid>
            <description>Spiral notebooks should be avoided.</description>
            <content:encoded><p>Spiral notebooks should be avoided.</p></content:encoded>
            <wfw:commentRss>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/feed/</wfw:commentRss>
            <slash:comments>0</slash:comments>
            <creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>

            <enclosure url="https://www.example.com/item.mp3" length="123456789" type="audio/mpeg" />

        </item>
        <item>
            <title>Skipped Item</title>
            <comments>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/#comments</comments>
            <dc:creator>dlarochelle</dc:creator>
            <category><![CDATA[Uncategorized]]></category>
            <description>
                One of the things that I learned in 2011 is that spiral notebooks should be avoid where
                ever possible.
            </description>
            <content:encoded>
                <p>One of the things that I learned in 2011 is that spiral notebooks should be avoid
                where ever possible. This post will detail why I’ve switched to using wireless bound
                notebooks exclusively.</p>
            </content:encoded>
            <wfw:commentRss>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/feed/</wfw:commentRss>
            <slash:comments>0</slash:comments>
        <creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>                        
        </item>
    </channel>
</rss>"""

    test_output = {
        'media_id': 1,
        'stories_id': 1,
        'url': (
            'https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-'
            'notebooks/'
        ),
        'title': '(no title)',
        'guid': 'http://blogs.law.harvard.edu/dlarochelle/?p=350',
        'description': '<p>Spiral notebooks should be avoided.</p>',
        'full_text_rss': False,
        'language': None,
    }

    test_medium = create_test_medium(db=db, label='downloads test')
    test_feed = create_test_feed(db, label='downloads test', medium=test_medium)
    test_download_feed = create_download_for_feed(db=db, feed=test_feed)

    handler = DownloadFeedPodcastHandler()
    new_story_ids = handler.add_stories_from_feed(
        db=db,
        download=test_download_feed,
        content=test_feed_input,
    )
    assert new_story_ids

    stories = []
    for stories_id in new_story_ids:
        stories.append(db.find_by_id(table='stories', object_id=stories_id))

    stories = [
        {k: v for k, v in d.items() if k not in {'publish_date', 'collect_date', 'normalized_title_hash'}}
        for d in stories
    ]

    print(f"Got stories: {stories}")

    assert stories == [test_output]

    story_enclosures = db.select(table='story_enclosures', what_to_select='*').hashes()
    assert len(story_enclosures) == 1

    enclosure = story_enclosures[0]
    assert enclosure['stories_id'] == 1
    assert enclosure['url'] == 'https://www.example.com/item.mp3'
    assert enclosure['mime_type'] == 'audio/mpeg'
    assert enclosure['length'] == 123456789

    # Confirm that the stories get deduplicated properly
    new_story_ids = handler.add_stories_from_feed(
        db=db,
        download=test_download_feed,
        content=test_feed_input,
    )
    assert not new_story_ids

    # Confirm that no new enclosures were added for existing stories
    story_enclosures = db.select(table='story_enclosures', what_to_select='*').hashes()
    assert len(story_enclosures) == 1
