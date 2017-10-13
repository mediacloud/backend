from bs4 import BeautifulSoup
from mediawords.date_guesser.html import get_tag_checkers, _make_tag_checker


def test__make_tag_checker():
    test_html = '<crazytown strange_class="strange_value" datestring="some_date"></crazytown>'
    tag_checker = _make_tag_checker('crazytown', {'strange_class': 'strange_value'}, 'datestring')
    soup = BeautifulSoup(test_html, 'lxml')
    assert tag_checker(soup) == 'some_date'

    # Empty html should not extract anything
    assert tag_checker(BeautifulSoup('', 'lxml')) is None


def test_get_tag_checkers():
    test_case ='''
    <html><head>
    <meta property="article:published" content='0'>
    <meta itemprop="datePublished" content='1'>
    <time itemprop="datePublished" datetime='2'>
    <meta property="article:published_time" content='3'>
    <meta name="DC.date.published" content='4'>
    <meta name="pubDate" content='5'>
    <time class="buzz-timestamp__time js-timestamp__time" data-unix='6'>
    <abbr class="published" title='7'>
    <time class="timestamp" datetime='8'>
    <meta property="nv:date" content='9'>
    </head></html>
    '''
    soup = BeautifulSoup(test_case, 'lxml')
    tag_checkers = get_tag_checkers()
    for idx, tag_checker in enumerate(tag_checkers):
        assert tag_checker(soup) == str(idx)


