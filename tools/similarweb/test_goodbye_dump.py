from similarweb.goodbye_dump import _url_domain


def test_url_domain():
    assert _url_domain('http://www.nytimes.com/abc.html') == 'nytimes.com'
    assert _url_domain('http://cyber.law.harvard.edu/') == 'cyber.law.harvard.edu'
    assert _url_domain('http://cyber.law.harvard.edu:80/') == 'cyber.law.harvard.edu'
    assert _url_domain('http://CYBER.LAW.HARVARD.EDU:80/') == 'cyber.law.harvard.edu'
    assert _url_domain('https://cyber.law.harvard.edu:443/') == 'cyber.law.harvard.edu'
    assert _url_domain('https://cyber.law.harvard.edu:12345/') == 'cyber.law.harvard.edu'
    assert _url_domain('http://www.cyber.law.harvard.edu/') == 'cyber.law.harvard.edu'
    assert _url_domain('http://www.gazeta.ru/') == 'gazeta.ru'
    assert _url_domain('http://www.whitehouse.gov/'), 'www.whitehouse.gov'
    assert _url_domain('http://info.info/') == 'info.info'
    assert _url_domain('http://blog.yesmeck.com/jquery-jsonview/') == 'blog.yesmeck.com'
    assert _url_domain('http://status.livejournal.org/') == 'status.livejournal.org'
    # noinspection PyTypeChecker
    assert _url_domain(None) is None
    assert _url_domain('not an URL') is None
