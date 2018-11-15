import datetime
import textwrap

from mediawords.test.hash_server import HashServer
from mediawords.util.log import create_logger
from mediawords.util.network import random_unused_port
from sitemap_feeds.sitemap.objects import (
    IndexRobotsTxtSitemap,
    StoriesXMLSitemap,
    IndexXMLSitemap,
    SitemapStory,
    InvalidSitemap,
)
from sitemap_feeds.sitemap.tree import sitemap_tree_for_homepage

# FIXME invalid XML (ending prematurely)
# FIXME gzip sitemaps
# FIXME various exotic properties
# FIXME XML vulnerabilities with Expat
# FIXME XML namespaces


log = create_logger(__name__)


def test_sitemap_tree_for_homepage():
    test_port = random_unused_port()
    test_url = 'http://localhost:%d' % test_port

    # Publication / "last modified" date
    test_date_datetime = datetime.datetime(
        year=2009, month=12, day=17, hour=12, minute=4, second=56,
        tzinfo=datetime.timezone(datetime.timedelta(seconds=7200)),
    )
    test_date_str = test_date_datetime.isoformat()

    test_publication_name = 'Test publication'
    test_publication_language = 'en'

    pages = {
        '/': 'This is a homepage.',

        '/robots.txt': {
            'header': 'Content-Type: text/plain',
            'content': textwrap.dedent("""
                    User-agent: *
                    Disallow: /whatever
                    
                    Sitemap: {base_url}/sitemap_pages.xml
                    Sitemap: {base_url}/sitemap_news_index_1.xml
                """.format(base_url=test_url)).strip(),
        },

        # One sitemap for random static pages
        '/sitemap_pages.xml': {
            'header': 'Content-Type: application/xml',
            'content': textwrap.dedent("""
                <?xml version="1.0" encoding="UTF-8"?>
                <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
                    <url>
                        <loc>{base_url}/about.html</loc>
                        <lastmod>2005-01-01</lastmod>
                        <changefreq>monthly</changefreq>
                        <priority>0.8</priority>
                    </url>
                    <url>
                        <loc>{base_url}/contact.html</loc>
                        <lastmod>2005-01-01</lastmod>
                        <changefreq>monthly</changefreq>
                        <priority>0.8</priority>
                    </url>
                </urlset> 
            """.format(base_url=test_url)).strip(),
        },

        # Index sitemap pointing to sitemaps with stories
        '/sitemap_news_index_1.xml': {
            'header': 'Content-Type: application/xml',
            'content': textwrap.dedent("""
                <?xml version="1.0" encoding="UTF-8"?>
                <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
                    <sitemap>
                        <loc>{base_url}/sitemap_news_1.xml</loc>
                        <lastmod>{last_modified}</lastmod>
                    </sitemap>
                    <sitemap>
                        <loc>{base_url}/sitemap_news_index_2.xml</loc>
                        <lastmod>{last_modified}</lastmod>
                    </sitemap>
                </sitemapindex>
            """.format(base_url=test_url, last_modified=test_date_str)).strip(),
        },

        # First sitemap with actual stories
        '/sitemap_news_1.xml': {
            'header': 'Content-Type: application/xml',
            'content': textwrap.dedent("""
                <?xml version="1.0" encoding="UTF-8"?>
                <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
                        xmlns:news="http://www.google.com/schemas/sitemap-news/0.9"
                        xmlns:xhtml="http://www.w3.org/1999/xhtml">
                    
                    <url>
                        <loc>{base_url}/news/foo.html</loc>
                        <xhtml:link rel="alternate"
                                    media="only screen and (max-width: 640px)"
                                    href="{base_url}/news/foo.html?mobile=1" />
                        <news:news>
                            <news:publication>
                                <news:name>{publication_name}</news:name>
                                <news:language>{publication_language}</news:language>
                            </news:publication>
                            <news:publication_date>{publication_date}</news:publication_date>
                            <news:title>Foo &lt;foo&gt;</news:title>    <!-- HTML entity decoding -->
                        </news:news>
                    </url>
                    
                    <!-- Has a duplicate story in /sitemap_news_2.xml -->
                    <url>
                        <loc>{base_url}/news/bar.html</loc>
                        <xhtml:link rel="alternate"
                                    media="only screen and (max-width: 640px)"
                                    href="{base_url}/news/bar.html?mobile=1" />
                        <news:news>
                            <news:publication>
                                <news:name>{publication_name}</news:name>
                                <news:language>{publication_language}</news:language>
                            </news:publication>
                            <news:publication_date>{publication_date}</news:publication_date>
                            <news:title>Bar &amp; bar</news:title>
                        </news:news>
                    </url>

                </urlset>
            """.format(
                base_url=test_url,
                publication_name=test_publication_name,
                publication_language=test_publication_language,
                publication_date=test_date_str,
            )).strip(),
        },

        # Another index sitemap pointing to a second sitemaps with stories
        '/sitemap_news_index_2.xml': {
            'header': 'Content-Type: application/xml',
            'content': textwrap.dedent("""
                <?xml version="1.0" encoding="UTF-8"?>
                <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
                
                    <sitemap>
                        <loc>{base_url}/sitemap_news_2.xml</loc>
                        <lastmod>{last_modified}</lastmod>
                    </sitemap>
    
                    <!-- Nonexistent sitemap -->
                    <sitemap>
                        <loc>{base_url}/sitemap_news_nonexistent.xml</loc>
                        <lastmod>{last_modified}</lastmod>
                    </sitemap>
                    
                </sitemapindex>
            """.format(base_url=test_url, last_modified=test_date_str)).strip(),
        },

        # First sitemap with actual stories
        '/sitemap_news_2.xml': {
            'header': 'Content-Type: application/xml',
            'content': textwrap.dedent("""
                <?xml version="1.0" encoding="UTF-8"?>
                <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
                        xmlns:news="http://www.google.com/schemas/sitemap-news/0.9"
                        xmlns:xhtml="http://www.w3.org/1999/xhtml">
    
                    <!-- Has a duplicate story in /sitemap_news_1.xml -->
                    <url>
                        <loc>{base_url}/news/bar.html</loc>
                        <xhtml:link rel="alternate"
                                    media="only screen and (max-width: 640px)"
                                    href="{base_url}/news/bar.html?mobile=1" />
                        <news:news>
                            <news:publication>
                                <news:name>{publication_name}</news:name>
                                <news:language>{publication_language}</news:language>
                            </news:publication>
                            <news:publication_date>{publication_date}</news:publication_date>
                            <news:title>Bar &amp; bar</news:title>
                        </news:news>
                    </url>
    
                    <url>
                        <loc>{base_url}/news/baz.html</loc>
                        <xhtml:link rel="alternate"
                                    media="only screen and (max-width: 640px)"
                                    href="{base_url}/news/baz.html?mobile=1" />
                        <news:news>
                            <news:publication>
                                <news:name>{publication_name}</news:name>
                                <news:language>{publication_language}</news:language>
                            </news:publication>
                            <news:publication_date>{publication_date}</news:publication_date>
                            <news:title><![CDATA[Bąž]]></news:title>    <!-- CDATA and UTF-8 -->
                        </news:news>
                    </url>
    
                </urlset>
            """.format(
                base_url=test_url,
                publication_name=test_publication_name,
                publication_language=test_publication_language,
                publication_date=test_date_str,
            )).strip(),
        },
    }

    # noinspection PyArgumentList
    expected_sitemap_tree = IndexRobotsTxtSitemap(
        url='{}/robots.txt'.format(test_url),
        sub_sitemaps=[
            StoriesXMLSitemap(
                url='{}/sitemap_pages.xml'.format(test_url),
                stories=[],  # Pages sitemap is expected to not have any news stories
            ),
            IndexXMLSitemap(
                url='{}/sitemap_news_index_1.xml'.format(test_url),
                sub_sitemaps=[
                    StoriesXMLSitemap(
                        url='{}/sitemap_news_1.xml'.format(test_url),
                        stories=[
                            SitemapStory(
                                url='{}/news/foo.html'.format(test_url),
                                title='Foo <foo>',
                                publish_date=test_date_datetime,
                                publication_name=test_publication_name,
                                publication_language=test_publication_language,
                            ),
                            SitemapStory(
                                url='{}/news/bar.html'.format(test_url),
                                title='Bar & bar',
                                publish_date=test_date_datetime,
                                publication_name=test_publication_name,
                                publication_language=test_publication_language,
                            ),
                        ]
                    ),
                    IndexXMLSitemap(
                        url='{}/sitemap_news_index_2.xml'.format(test_url),
                        sub_sitemaps=[
                            StoriesXMLSitemap(
                                url='{}/sitemap_news_2.xml'.format(test_url),
                                stories=[
                                    SitemapStory(
                                        url='{}/news/bar.html'.format(test_url),
                                        title='Bar & bar',
                                        publish_date=test_date_datetime,
                                        publication_name=test_publication_name,
                                        publication_language=test_publication_language,
                                    ),
                                    SitemapStory(
                                        url='{}/news/baz.html'.format(test_url),
                                        title='Bąž',
                                        publish_date=test_date_datetime,
                                        publication_name=test_publication_name,
                                        publication_language=test_publication_language,
                                    ),
                                ],
                            ),
                            InvalidSitemap(
                                url='{}/sitemap_news_nonexistent.xml'.format(test_url),
                                reason=(
                                    'Unable to fetch sitemap from {base_url}/sitemap_news_nonexistent.xml: '
                                    '404 Not Found'
                                ).format(base_url=test_url),
                            ),
                        ],
                    ),
                ],
            ),
        ],
    )

    hs = HashServer(port=test_port, pages=pages)
    hs.start()

    actual_sitemap_tree = sitemap_tree_for_homepage(homepage_url=test_url)

    hs.stop()

    # PyCharm is not that amazing at formatting object diffs:
    #
    # expected_lines = str(expected_sitemap_tree).split()
    # actual_lines = str(actual_sitemap_tree).split()
    # diff = difflib.ndiff(expected_lines, actual_lines)
    # diff_str = '\n'.join(diff)
    # assert expected_lines == actual_lines

    assert expected_sitemap_tree == actual_sitemap_tree
