from mediawords.util.similarweb.domain import domain_from_url


def test_domain_from_url():
    assert domain_from_url('http://www.nytimes.com/abc.html') == 'nytimes.com'
    assert domain_from_url('http://www.republicoftogo.com/') == 'republicoftogo.com'
    assert domain_from_url('http://www.fbi.gov') == 'fbi.gov'
    assert domain_from_url('http://cyber.law.harvard.edu/') == 'harvard.edu'
    assert domain_from_url('http://cyber.law.harvard.edu:80/') == 'harvard.edu'
    assert domain_from_url('http://CYBER.LAW.HARVARD.EDU:80/') == 'harvard.edu'
    assert domain_from_url('https://cyber.law.harvard.edu:443/') == 'harvard.edu'
    assert domain_from_url('https://cyber.law.harvard.edu:12345/') == 'harvard.edu'
    assert domain_from_url('http://www.cyber.law.harvard.edu/') == 'harvard.edu'
    assert domain_from_url('http://www.gazeta.ru/') == 'gazeta.ru'
    assert domain_from_url('http://www.whitehouse.gov/') == 'whitehouse.gov'
    assert domain_from_url('http://whitehouse.gov/') == 'whitehouse.gov'
    assert domain_from_url('http://info.info/') == 'info.info'
    assert domain_from_url('http://blog.yesmeck.com/jquery-jsonview/') == 'yesmeck.com'
    assert domain_from_url('http://status.livejournal.org/') == 'livejournal.org'
    assert domain_from_url('http://blot-luk.livejournal.com') == 'blot-luk.livejournal.com'
    # noinspection PyTypeChecker
    assert domain_from_url(None) is None
    assert domain_from_url('not an URL') is None
