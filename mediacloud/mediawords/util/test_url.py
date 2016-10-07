from mediawords.util.url import *


def test_fix_common_url_mistakes():
    urls = {
        # "http://http://"
        'http://http://www.al-monitor.com/pulse': 'http://www.al-monitor.com/pulse',

        # With only one slash ("http:/www.")
        'http:/www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled':
            'http://www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled',

        # missing / before ?
        'http://foo.bar?baz=bat': 'http://foo.bar/?baz=bat',
    }

    for orig_url, fixed_url in urls.items():
        # Fix once
        assert fix_common_url_mistakes(orig_url) == fixed_url

        # Try fixing the same URL twice, see what happens
        assert fix_common_url_mistakes(fix_common_url_mistakes(orig_url)) == fixed_url
