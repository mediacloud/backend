from mediawords.dbi.stories.parse_tweets import find_tweets_in_html, _is_tweet_embedded


def test_find_tweets_in_html() -> None:
    """Tests finding tweets in html"""
    html_examples = {
        '</span><a href="https://twitter.com/DrDavidDuke/status/799624219831058432?reffoo" target="_blank">':
            [{'user':'DrDavidDuke', 
              'id': '799624219831058432', 
              'embedded': False}],
        '<a href="https://twitter.com/foo/status/3458"><a href="https://twitter.com/MerriamWebster/status/2648">': 
            [{'user': 'foo', 
              'id': '3458', 
              'embedded': False}, 
             {'user': 'MerriamWebster', 
              'id': '2648', 
              'embedded': False}],
        'href="https://twitter.com/realDonaldTrump"data-component="externalLink"rel="noopener">@realDonaldTrump': 
            []
    }

    for html_example in html_examples:
        assert find_tweets_in_html(html_example) == html_examples[html_example]


def test_is_tweet_embedded() -> None:
    """Tests if the regular expressions still work to find embedded tweets"""

    input_examples = {
        'Test 1':
            ['pike', '102420',
             '(@pike)a href="https://twitter.com/pike/status/102420 "https://platform.twitter.com/widgets.js"', 
             True],
        'Test 2':
            ['realDonaldTrump', '1024205453788557312',
             'f="https://twitter.com/realDonaldTrump/status/1061168803218948096" target="_blank">tweet</a>, P', 
             False], 
        'Test 3':
            ['MikeDrucker', '86980998', 
             'href="https://twitter.com/realDonaldTrump/status/8698?ref_src=twsrc%5Etfw">"https://platform.twitter.com/widgets.js""twitter-tweet">(@MikeDrucker)://twitter.com/MikeDrucker/status/86980998?ref_src=/platform.twitter.com/widgets.js',
             True]
}

    for input_example in input_examples:
        response =  _is_tweet_embedded(input_examples[input_example][0], input_examples[input_example][1], input_examples[input_example][2]) 
        assert response == input_examples[input_example][3]




