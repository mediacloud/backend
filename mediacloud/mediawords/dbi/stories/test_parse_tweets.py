from mediawords.dbi.stories.parse_tweets import find_tweets_in_html, _find_if_tweet_is_embedded


def test_find_tweets_in_html(self) -> None:
    """Tests finding tweets in html"""
    html_examples = {
        '</span><a href="https://twitter.com/DrDavidDuke/status/799624219831058432?reffoo" target="_blank">':
            [{'user':'DrDavidDuke', 
              'id': '799624219831058432', 
              'html': '<html>foo</html',
              'embedded': False}],
        '<a href="https://twitter.com/foo/status/3458"><a href="https://twitter.com/foo/status/2458">': 
            [{'user': 'realDonaldTrump', 
              'id': '3458', 
              'embedded': True}, 
             {'user': 'MerriamWebster', 
              'id': '2648', 
              'embedded': True}],
        'To his critics, the tweets sent from his personal handle -- <a \
    href="https://twitter.com/realDonaldTrump" target="_blank" data-componen\
    t="externalLink" rel="noopener">@realDonaldTrump</a> -- r': 
            []
    }

    for html_example in html_examples:
        assert find_tweets_in_html(html_example) == html_examples[html_example]


def test_find_if_tweet_is_embedded(self) -> None:
    """Tests if the regular expressions still work to find embedded tweets"""

    input_examples = {
        ['pikelet', '1024205453788557312',
         'p>&mdash; Advanced Pikelet Threat (@pikelet)\
    a href=\\\\\\"https://twitter.com/pikelet/status/1024205453788557312?re\
    f_src=twsrc%5Etfw\\\\\\">July 31, 2018&lt;/a>&lt;/blockquote>\\\\n&lt;sc\
    ript async src=\\\\\\"https://platform.twitter.com/widgets.js\\\\\\"']: 
        True,

        ['realDonaldTrump', '1024205453788557312',
         'reasons behind these more massive fires. In a November <a hrei\
    f="https://twitter.com/realDonaldTrump/status/1061168803218948096" targe\
    t="_blank">tweet</a>, P']: 
        False,

        ['MikeDrucker', '869809982610354176', 
         'href="https://twitter.com/realDonaldTrump/status/8698583334775\
    23458?ref_src=twsrc%5Etfw">May 31, 2017</a></blockquote> <script async="\
    " src="https://platform.twitter.com/widgets.js""twitter-tweet"><p lang="\
    en" dir="ltr">This is the way the world ends.<br />This is the way the w\
    orld ends.<br />This is the way the world ends. <br />Not with a bang bu\
    t a covfefe.<br /><br />-T.S. Eliot</p>— Mike Drucker (@MikeDrucker) <a \
    href="https://twitter.com/MikeDrucker/status/869809982610354176?ref_src=\
    twsrc%5Etfw">May 31, 2017</a></blockquote> <script async="" src="https:/\
    /platform.twitter.com/widgets.js']: 
        True

}

    for input_example in input_examples:
        assert _find_if_tweet_is_embedded(input_example[0], 
input_example[1], input_example[2]) == input_examples[html_example]




