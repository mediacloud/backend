from mediawords.util.mail_message.topics_messages import TopicSpiderUpdateMessage


def test_topic_spider_update_email():
    topic_name = 'Foo Bar Baz & <script></script>'
    topic_url = 'https://topics.com/topic?ab=cd&ef=gh'
    topic_spider_status = 'Abc def & <script></script>'

    message = TopicSpiderUpdateMessage(
        to='nowhere@mediacloud.org',
        topic_name=topic_name,
        topic_url=topic_url,
        topic_spider_status=topic_spider_status,
    )

    assert message.subject is not None
    assert len(message.subject) > 3
    assert '{{' not in message.subject  # no Jinja2 variable placeholders

    assert message.text_body is not None
    assert len(message.text_body) > 100

    assert message.html_body is not None
    assert len(message.html_body) > 100

    assert topic_name in message.text_body
    assert topic_url in message.text_body
    assert topic_spider_status in message.text_body

    assert topic_name not in message.html_body  # should be escaped
    assert 'Foo Bar Baz &amp; &lt;script&gt;&lt;/script&gt;' in message.html_body

    assert topic_url not in message.html_body  # should be escaped
    assert 'https://topics.com/topic?ab=cd&amp;ef=gh' in message.html_body

    assert topic_spider_status not in message.html_body  # should be escaped
    assert 'Abc def &amp; &lt;script&gt;&lt;/script&gt;' in message.html_body
