import re

import timeout_decorator

from extract_article_from_page import (
    extractor_name,
    extract_article_from_page,
    replace_control_nonprintable_characters,
)


def test_extractor_name():
    name = extractor_name()
    assert re.match(r'^readability-lxml-[\d.]{3,7}?$', name)

    # Test caching
    cached_name = extractor_name()
    assert name == cached_name


# noinspection SpellCheckingInspection
def test_extract_article_from_page():
    assert extract_article_from_page('') == ''
    # noinspection PyTypeChecker
    assert extract_article_from_page(None) == ''

    # No HTML
    input_html = 'Kim Kardashian'
    expected_title = ''
    expected_summary = '<body id="readabilityBody"><p>Kim Kardashian</p></body>'
    extracted_text = extract_article_from_page(input_html)
    assert extracted_text == "%s\n\n%s" % (expected_title, expected_summary)

    # Simple HTML 5
    input_html = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Kim Kardashian</title>
    <meta name="description" content="Foo bar baz.">
    <meta name="keywords" content="foo, bar, baz">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="apple-itunes-app" content="app-id=993465092">
    <!--[if lt IE 9]>
        <script src="/assets/themes/bootstrap/resources/respond/Respond.min.js"></script>
    <![endif]-->

    <link href="/assets/themes/bootstrap/resources/lightbox/css/lightbox.css" rel="stylesheet">
    <style type="text/css" media="all">

        @media (min-width: 1200px) {
            .container {
                width: 970px;
            }
        }

        /* Center carousel screenshots */
        .carousel-inner > .item > img {
            margin: 0 auto;
        }

        footer {
            padding-bottom: 1em;
        }

    </style>
</head>

<body>

    <script>(function(d, s, id) {
        var js, fjs = d.getElementsByTagName(s)[0];
        if (d.getElementById(id)) return;
        js = d.createElement(s); js.id = id;
        js.src = "//connect.facebook.net/lt_LT/sdk.js#xfbml=1&version=v2.3&appId=1582189855364776";
        fjs.parentNode.insertBefore(js, fjs);
        }(document, 'script', 'facebook-jssdk'));
    </script>

    <nav class="navbar navbar-default" role="navigation">Chloe Kardashian</nav>

    <!-- The following must be treated as content -->
    <article class="container"><p>Kim Kardashian</p></article>

    <footer>Some other Kardashian</footer>

    <script>
        (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
        (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
        m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
        })(window,document,'script','//www.google-analytics.com/analytics.js','ga');

        ga('create', 'UA-55603806-1', 'auto');
        ga('send', 'pageview');
    </script>

    <script src="/assets/themes/bootstrap/resources/jquery/jquery.min.js"></script>
    <script src="/assets/themes/bootstrap/resources/bootstrap/js/bootstrap.min.js"></script>
    <script src="/assets/themes/bootstrap/resources/lightbox/lightbox.min.js"></script>

</body>
</html>"""

    extracted_text = extract_article_from_page(input_html)

    assert re.match(
        r"""
            Kim\ Kardashian\s*?
            <body.*?>\s*?
                <nav.*?>Chloe\ Kardashian</nav>\s*?
                <article.*?><p>Kim\ Kardashian</p></article>\s*?
            </body>
        """,
        extracted_text,
        flags=re.X
    )


def test_replace_control_nonprintable_characters():
    # "Ḃ" is 0x1E02, and if the function happened to input as bytes (i.e. without UTF-8 awareness),
    # it might choose to strip 0x02 part, so we need to test for that
    unicode_character = "Ḃ"
    input_string = (b"\x00a\nb\r\nc\td\x7fe" + unicode_character.encode('utf-8') + b"f").decode('utf-8')
    replacement = 'xyz'
    expected_string = f"{replacement}a\nb\r\nc\td{replacement}e{unicode_character}f"
    actual_string = replace_control_nonprintable_characters(string=input_string, replacement=replacement)
    assert expected_string == actual_string


@timeout_decorator.timeout(seconds=5, use_signals=False)
def test_extract_article_from_page_null_bytes():
    null_bytes = '\x00' * 1024 * 1024 * 5
    html = '<html><body><p>foo' + null_bytes + '</p></body></html>'

    extracted_text = extract_article_from_page(html)

    assert re.search(r'foo', extracted_text, flags=re.X)


# make sure string with very long space range does not hang the extractor (triggered by a bug in
# readability for which we added a work around in extract_text.py)
@timeout_decorator.timeout(seconds=5, use_signals=False)
def test_extract_article_from_page_long_space():
    long_space = ' ' * 1000000
    html = '<html><body><p>foo' + long_space + '</p></body></html>'

    extracted_text = extract_article_from_page(html)

    assert re.search(r'foo', extracted_text, flags=re.X)


# Try out with different kinds of whitespace in a single sequence
@timeout_decorator.timeout(seconds=5, use_signals=False)
def test_extract_article_from_page_long_varied_whitespace():
    long_space = ' \n\t\r' * 1000000
    html = '<html><body><p>foo' + long_space + '</p></body></html>'

    extracted_text = extract_article_from_page(html)

    assert re.search(r'foo', extracted_text, flags=re.X)


# Try out with different kinds of whitespace in a single sequence
@timeout_decorator.timeout(seconds=5, use_signals=False)
def test_extract_article_from_page_nonprintable_characters():
    long_space = '\x00\x01\x02 ' * 1000000
    html = '<html><body><p>foo' + long_space + '</p></body></html>'

    extracted_text = extract_article_from_page(html)

    assert re.search(r'foo', extracted_text, flags=re.X)
