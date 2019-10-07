# noinspection PyProtectedMember
from topics_extract_story_links.extract_story_links import _get_links_from_html
from mediawords.util.url import is_http_url


def test_get_links_from_html():
    def test_links(html_: str, links_: list) -> None:
        assert _get_links_from_html(html_) == links_

    test_links('<a href="http://foo.com">', ['http://foo.com'])
    test_links('<link href="http://bar.com">', ['http://bar.com'])
    test_links('<img src="http://img.tag">', [])

    test_links('<a href="http://foo.com"/> <a href="http://bar.com"/>', ['http://foo.com', 'http://bar.com'])

    # transform nyt urls
    test_links('<a href="http://www3.nytimes.com/foo/bar">', ['http://www.nytimes.com/foo/bar'])

    # ignore relative urls
    test_links('<a href="/foo/bar">', [])

    # ignore invalid urls
    test_links(r'<a href="http:\\foo.bar">', [])

    # ignore urls from ignore pattern
    test_links('<a href="http://www.addtoany.com/http://foo.bar">', [])
    test_links('<a href="https://en.unionpedia.org/c/SOE_F_Section_timeline/vs/Special_Operations_Executive">', [])
    test_links('<a href="http://digg.com/submit/this">', [])
    test_links('<a href="http://politicalgraveyard.com/>', [])
    test_links('<a href="http://api.bleacherreport.com/api/v1/tags/cm-punk.json">', [])
    test_links('<a href="http://apidomain.com">', ['http://apidomain.com'])
    test_links('<a href="http://www.rumormillnews.com/cgi-bin/forum.cgi?noframes;read=54990">', [])
    test_links('<a href="http://tvtropes.org/pmwiki/pmwiki.php/Main/ClockTower">', [])
    test_links('<a href=https://twitter.com/account/suspended">', [])

    # sanity test to make sure that we are able to get all of the links from a real html page
    filename = '/opt/mediacloud/tests/data/html-strip/strip.html'
    with open(filename, 'r', encoding='utf8') as fh:
        html = fh.read()

    links = _get_links_from_html(html)
    assert len(links) == 300
    for link in links:
        assert is_http_url(link)
