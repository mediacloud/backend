from topics_base.stories import url_has_binary_extension


def test_url_has_binary_extension():
    """Test url_has_binary_extention()."""
    assert not url_has_binary_extension('http://google.com')
    assert not url_has_binary_extension('https://www.nytimes.com/trump-khashoggi-dead.html')
    assert not url_has_binary_extension('https://www.washingtonpost.com/war-has-not/_story.html?utm_term=.c6ddfa7f19')
    assert url_has_binary_extension('http://uproxx.files.wordpress.com/2017/06/push-up.jpg?quality=100&amp;w=1024')
    assert url_has_binary_extension('https://cdn.theatlantic.com/assets/media/files/shubeik_lubeik_byna_mohamed.pdf')
    assert url_has_binary_extension('https://i1.wp.com/7miradas.com/wp-content/uploads8/02/UHJ9OKM.png?resize=62%2C62')
