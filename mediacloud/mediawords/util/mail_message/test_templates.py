from mediawords.util.mail_message.templates import (
    AuthActivationNeededMessage, AuthActivatedMessage, AuthResetPasswordMessage,
    AuthAPIKeyResetMessage, TopicSpiderUpdateMessage, AuthPasswordChangedMessage)


def test_auth_activation_needed_email():
    full_name = 'Foo Bar Baz & <script></script>'
    activation_url = 'https://activation.com/activate?ab=cd&ef=gh'
    subscribe_to_newsletter = True

    message = AuthActivationNeededMessage(
        to='nowhere@mediacloud.org',
        full_name=full_name,
        activation_url=activation_url,
        subscribe_to_newsletter=subscribe_to_newsletter,
    )

    assert message.subject is not None
    assert len(message.subject) > 3

    assert message.text_body is not None
    assert len(message.text_body) > 100

    assert message.html_body is not None
    assert len(message.html_body) > 100

    assert full_name in message.text_body
    assert activation_url in message.text_body

    assert full_name not in message.html_body  # should be escaped
    assert 'Foo Bar Baz &amp; &lt;script&gt;&lt;/script&gt;' in message.html_body

    assert activation_url not in message.html_body  # should be escaped
    assert 'https://activation.com/activate?ab=cd&amp;ef=gh' in message.html_body


def test_auth_activated_email():
    full_name = 'Foo Bar Baz & <script></script>'

    message = AuthActivatedMessage(
        to='nowhere@mediacloud.org',
        full_name=full_name,
    )

    assert message.subject is not None
    assert len(message.subject) > 3

    assert message.text_body is not None
    assert len(message.text_body) > 100

    assert message.html_body is not None
    assert len(message.html_body) > 100

    assert full_name in message.text_body
    assert full_name not in message.html_body  # should be escaped
    assert 'Foo Bar Baz &amp; &lt;script&gt;&lt;/script&gt;' in message.html_body


def test_auth_reset_password_email():
    full_name = 'Foo Bar Baz & <script></script>'
    password_reset_url = 'https://password.com/password_reset?ab=cd&ef=gh'

    message = AuthResetPasswordMessage(
        to='nowhere@mediacloud.org',
        full_name=full_name,
        password_reset_url=password_reset_url,
    )

    assert message.subject is not None
    assert len(message.subject) > 3

    assert message.text_body is not None
    assert len(message.text_body) > 100

    assert message.html_body is not None
    assert len(message.html_body) > 100

    assert full_name in message.text_body
    assert password_reset_url in message.text_body

    assert full_name not in message.html_body  # should be escaped
    assert 'Foo Bar Baz &amp; &lt;script&gt;&lt;/script&gt;' in message.html_body

    assert password_reset_url not in message.html_body  # should be escaped
    assert 'https://password.com/password_reset?ab=cd&amp;ef=gh' in message.html_body


def test_auth_password_changed_email():
    full_name = 'Foo Bar Baz & <script></script>'

    message = AuthPasswordChangedMessage(
        to='nowhere@mediacloud.org',
        full_name=full_name,
    )

    assert message.subject is not None
    assert len(message.subject) > 3

    assert message.text_body is not None
    assert len(message.text_body) > 100

    assert message.html_body is not None
    assert len(message.html_body) > 100

    assert full_name in message.text_body
    assert full_name not in message.html_body  # should be escaped
    assert 'Foo Bar Baz &amp; &lt;script&gt;&lt;/script&gt;' in message.html_body


def test_auth_api_key_reset_email():
    full_name = 'Foo Bar Baz & <script></script>'

    message = AuthAPIKeyResetMessage(
        to='nowhere@mediacloud.org',
        full_name=full_name,
    )

    assert message.subject is not None
    assert len(message.subject) > 3

    assert message.text_body is not None
    assert len(message.text_body) > 100

    assert message.html_body is not None
    assert len(message.html_body) > 100

    assert full_name in message.text_body
    assert full_name not in message.html_body  # should be escaped
    assert 'Foo Bar Baz &amp; &lt;script&gt;&lt;/script&gt;' in message.html_body


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
