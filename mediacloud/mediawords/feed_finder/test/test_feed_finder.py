from mediawords.feed_finder import feed_finder
from mediawords.test.http.hash_server import HashServer
from mediawords.util.network import random_unused_port


def test__is_feed_url():
    assert not feed_finder._is_feed_url('nytimes.com')
    assert feed_finder._is_feed_url('nytimes.rss')
    assert not feed_finder._is_feed_url('rssnews.com')


def test__might_be_feed_url():
    assert not feed_finder._might_be_feed_url('nytimes.com')
    assert feed_finder._might_be_feed_url('nytimes.rss')
    assert feed_finder._might_be_feed_url('rssnews.com')


class TestFeedFinder(object):
    def setup_method(self):
        self.port = random_unused_port()
        self.base_url = 'http://localhost:{}'.format(self.port)
        self.regular_html_template = "<html><head>{head}</head><body>{body}</body></html>"
        self.rss_feed_template = '<link type="application/rss+xml" href="{}" />'
        self.regular_feed_page = '<?xml version="1.0"?> <rss version="2.0"></rss>'


    def test_is_feed(self):
        finder = feed_finder.FeedFinder(self.base_url, html=self.regular_feed_page)
        assert finder.is_feed()
        finder = feed_finder.FeedFinder(self.base_url, html=self.regular_html_template)
        assert not finder.is_feed()

    def test_html_property(self):
        link_map = {
            '': self.regular_html_template,
        }

        server = HashServer(port=self.port, pages=link_map)
        server.start()
        finder = feed_finder.FeedFinder(self.base_url)
        found_html = finder.html
        server.stop()
        assert found_html == self.regular_html_template

    def generate_server(self):
        feeds = (
            '/get_your_news_here.html',  # will be found in <head>
            '/atom.rss',  # will be found in <body>
            '/index.xml',  # hidden!  will still get spotted
        )

        non_feeds = (
            '/not_a_feed.rss',  # will be in <head>
            '/rss.atom',  # will be in <body>
            'atom.xml',  # hidden, but not 404
        )

        html = self.regular_html_template.format(
            head=self.rss_feed_template.format(feeds[0]),
            body='<a href="{}"></a>'.format(feeds[1])
        )

        assert feeds[0] in html
        assert feeds[1] in html
        assert feeds[2] not in html

        link_map = {
            '': html,
        }

        for feed in feeds:
            link_map[feed] = self.regular_feed_page

        for feed in non_feeds:
            link_map[feed] = self.regular_html_template

        server = HashServer(port=self.port, pages=link_map)
        return feeds, server

    def test_generate_feed_urls(self):
        feeds, server = self.generate_server()

        server.start()
        finder = feed_finder.FeedFinder(self.base_url)
        found_feeds = list(finder.generate_feed_urls())
        server.stop()

        assert len(found_feeds) == len(feeds)

    def test_generate_feed_urls_function(self):
        feeds, server = self.generate_server()

        server.start()
        found_feeds = list(feed_finder.generate_feed_urls(self.base_url))
        server.stop()

        assert len(found_feeds) == len(feeds)

    def test_generate_feed_urls_not_a_page(self):
        feeds, server = self.generate_server()

        server.start()
        finder = feed_finder.FeedFinder(self.base_url + '/what_is_this_even')
        found_feeds = list(finder.generate_feed_urls())
        server.stop()

        assert len(found_feeds) == 0

    def test_generate_feed_urls_on_feed(self):
        feeds, server = self.generate_server()

        server.start()
        finder = feed_finder.FeedFinder(self.base_url + feeds[0])
        found_feeds = list(finder.generate_feed_urls())
        server.stop()

        assert len(found_feeds) == 1

    def test_find_feed_url(self):
        feeds, server = self.generate_server()

        server.start()
        url = feed_finder.find_feed_url(self.base_url)
        server.stop()
        assert url == self.base_url + feeds[0]

    def test_find_link_feeds(self):
        num_feeds = 4
        feed_urls = []
        # note that we do NOT eliminate duplicates at this level
        for _ in range(num_feeds):
            feed_urls.append(self.rss_feed_template.format('http://whatever.com'))

        html = self.regular_html_template.format(head='\n'.join(feed_urls), body='')
        finder = feed_finder.FeedFinder(self.base_url, html=html)
        assert len(list(finder.find_link_feeds())) == num_feeds
        assert len(list(finder.find_anchor_feeds())) == 0

    def test_find_anchor_feeds(self):
        num_feeds = 4
        feed_urls = []
        # we should find these four links
        for feed in range(num_feeds):
            feed_urls.append('<a href="http://{}.rss"></a>'.format(feed))

        # but will not flag this one, since it does not look like a feed
        feed_urls.append('<a href="https://not_an_example.com"></a>')

        html = self.regular_html_template.format(head='', body='\n'.join(feed_urls))
        finder = feed_finder.FeedFinder(self.base_url, html=html)
        assert len(list(finder.find_link_feeds())) == 0
        assert len(list(finder.find_anchor_feeds())) == num_feeds

    def test_guess_feed_links(self):
        # even empty page has some guesses
        finder = feed_finder.FeedFinder(self.base_url, html=self.regular_html_template)
        guessed_links = list(finder.guess_feed_links())
        assert len(guessed_links) > 0
        for feed_link in guessed_links:
            assert self.base_url in feed_link

    def test_empty_page(self):
        finder = feed_finder.FeedFinder(self.base_url, html=self.regular_html_template)
        # Page has no links, so should fail
        assert finder.find_feed_url() is None
