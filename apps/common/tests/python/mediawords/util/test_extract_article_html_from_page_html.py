from mediawords.util.extract_article_from_page import extract_article_html_from_page_html


def test_extract_article_html_from_page_html():
    content = """
    <html>
    <head>
    <title>I'm a test</title>
    </head>
    <body>
    <p>Hi test, I'm dad!</p>
    </body>
    </html>        
    """

    response = extract_article_html_from_page_html(content=content)

    assert response
    assert 'extracted_html' in response
    assert 'extractor_version' in response

    assert "I'm a test" in response['extracted_html']
    assert "Hi test, I'm dad!" in response['extracted_html']
    assert 'readabilityBody' in response['extracted_html']  # <body id="readabilityBody">

    assert "readability-lxml" in response['extractor_version']
