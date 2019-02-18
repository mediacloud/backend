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
