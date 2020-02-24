import dataclasses
from typing import List, Dict, Any

from crawler_fetcher.handlers.feed_syndicated import DownloadFeedSyndicatedHandler
from mediawords.db import connect_to_db, DatabaseHandler


def _convert_to_local_time_zone(db: DatabaseHandler, sql_date: str) -> str:
    date = db.query("""
        SELECT (%(sql_date)s::timestamptz)::timestamp
    """, {
        'sql_date': sql_date,
    }).flat()
    return date[0]


@dataclasses.dataclass
class _TestFeedStory(object):
    test_name: str
    media_id: int
    publish_date: str
    feed_input: str
    test_output: List[Dict[str, Any]]


def test_get_stories_from_syndicated_feed():
    db = connect_to_db()

    test_cases = [
        _TestFeedStory(
            test_name='standard_single_item',
            media_id=1,
            publish_date=_convert_to_local_time_zone(db=db, sql_date='2012-01-09 06:20:10-0'),
            feed_input="""
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
                            <title>Why Life is Too Short for Spiral Notebooks</title>
                    
                            <link>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/</link>
                            <comments>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/#comments</comments>
                            <pubDate>Mon, 09 Jan 2012 06:20:10 +0000</pubDate>
                            <dc:creator>dlarochelle</dc:creator>
                            <category><![CDATA[Uncategorized]]></category>
                            <guid isPermaLink="false">http://blogs.law.harvard.edu/dlarochelle/?p=350</guid>
                            <description>Spiral notebooks should be avoided.</description>
                            <content:encoded><p>Spiral notebooks should be avoided.</p></content:encoded>
                            <wfw:commentRss>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/feed/</wfw:commentRss>
                            <slash:comments>0</slash:comments>
                            <creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
                        </item>
                    </channel>
                </rss>
            """,
            test_output=[
                {
                    # 'collect_date': '2012-01-10T20:03:48',
                    'media_id': 1,
                    'publish_date': _convert_to_local_time_zone(db=db, sql_date='2012-01-09 06:20:10-0'),
                    'url': (
                        'https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-'
                        'notebooks/'
                    ),
                    'title': 'Why Life is Too Short for Spiral Notebooks',
                    'guid': 'http://blogs.law.harvard.edu/dlarochelle/?p=350',
                    'description': '<p>Spiral notebooks should be avoided.</p>',
                    'enclosures': [],
                },
            ],
        ),
        _TestFeedStory(
            test_name='no title or time plus enclosure',
            media_id=1,
            publish_date=_convert_to_local_time_zone(db=db, sql_date='2012-01-09 06:20:10-0'),
            feed_input="""
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
                </rss>
            """,
            test_output=[
                {
                    # 'collect_date': '2012-01-10T20:03:48',
                    'media_id': 1,
                    'publish_date': _convert_to_local_time_zone(db=db, sql_date='2012-01-09 06:20:10-0'),
                    'url': (
                        'https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-'
                        'notebooks/'
                    ),
                    'title': '(no title)',
                    'guid': 'http://blogs.law.harvard.edu/dlarochelle/?p=350',
                    'description': '<p>Spiral notebooks should be avoided.</p>',
                    'enclosures': [
                        {
                            'url': 'https://www.example.com/item.mp3',
                            'length': 123456789,
                            'mime_type': 'audio/mpeg',
                        }
                    ],
                }
            ],
        ),
    ]

    for test_case in test_cases:
        stories = DownloadFeedSyndicatedHandler._get_stories_from_syndicated_feed(
            content=test_case.feed_input,
            media_id=test_case.media_id,
            download_time=test_case.publish_date,
        )

        stories = [{k: v for k, v in d.items() if k != 'collect_date'} for d in stories]

        assert stories[0]['publish_date'] == test_case.test_output[0]['publish_date'], "publish_date"
        assert stories == test_case.test_output
