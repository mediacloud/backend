# noinspection PyProtectedMember
from facebook_fetch_story_stats import _get_url_stats


# noinspection HttpUrlsUsage
def test_bogus_urls():
    """Test with URLs that might fail."""
    bogus_urls = [
        # URLs with #fragment
        'http://www.nbcnews.com/#/health/health-news/inside-ebola-clinic-doctors-fight-out-control-virus-%20n150391',
        'http://www.nbcnews.com/#/health/',
        'http://www.nbcnews.com/#/health',
        'http://www.nbcnews.com/#/',
        'http://foo.com/#/bar/',

        # URLs with ~tilde
        'http://cyber.law.harvard.edu/~lvaliukas/test.html/',
        'http://cyber.law.harvard.edu/~lvaliukas/test.html/#/foo',
        (
            'http://feeds.please-note-that-this-url-is-not-gawker.com/~r/gizmodo/full/~3/qIhlxlB7gmw/'
            'foo-bar-baz-1234567890/'
        ),
        'http://feeds.boingboing.net/~r/boingboing/iBag/~3/W1mgVFzEwm4/last-chance-to-save-net-neutra.html/',

        # URLs with #fragment that's about to be removed
        'http://www.macworld.com/article/2154541/podcast-we-got-the-beats.html#tk.rss_all',

        # Gawker's feed URLs
        (
            'http://feeds.gawker.com/~r/gizmodo/full/~3/qIhlxlB7gmw/'
            'how-to-yell-at-the-fcc-about-how-much-you-hate-its-net-1576943170'
        ),
        (
            'http://feeds.gawker.com/~r/gawker/full/~3/FjKCT99u_M8/'
            'wall-street-is-doing-devious-shit-while-america-sleeps-1679519880'
        ),

        # URL that don't return "share" or "og_object" keys
        (
            'http://feeds.chicagotribune.com/~r/chicagotribune/views/~3/weNQRdjizS8/'
            'sns-rt-us-usa-court-netneutrality-20140114,0,5487975.story'
        ),

        # Bogus URL with "http:/www" (fixable by fix_common_url_mistakes())
        'http:/www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled',

    ]

    for bogus_url in bogus_urls:
        try:
            _get_url_stats(bogus_url)
        except Exception as ex:
            assert False, f"Bogus URL '{bogus_url}' should have worked but didn't: {ex}"


# noinspection HttpUrlsUsage
def test_get_url_stats_normal_url():
    url = (
        'http://www.nytimes.com/interactive/2014/08/13/us/'
        'ferguson-missouri-town-under-siege-after-police-shooting.html'
    )
    stats = _get_url_stats(url=url)
    assert stats is not None, f"Stats should be set for URL '{url}'"
    assert stats.share_count > 0, f"Share could should be positive for URL '{url}'"


# noinspection HttpUrlsUsage
def test_get_url_stats_bogus_url():
    url = 'http://totally.bogus.url.123456'
    stats = _get_url_stats(url=url)
    assert stats is not None, f"Stats should be set for URL '{url}'"
    assert stats.share_count == 0, f"Share could should be 0 for URL '{url}'"
    assert stats.comment_count == 0, f"Comment could should be 0 for URL '{url}'"
