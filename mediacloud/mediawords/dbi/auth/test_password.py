import pytest

from mediawords.dbi.auth.password import (
    password_hash_is_valid,
    generate_password_hash,
    McAuthPasswordException,
    validate_new_password,
)
from mediawords.util.text import random_string


def test_password_hash_is_valid():
    with pytest.raises(McAuthPasswordException):
        # noinspection PyTypeChecker
        assert password_hash_is_valid(password_hash=None, password='secret') is False
    with pytest.raises(McAuthPasswordException):
        assert password_hash_is_valid(password_hash='not a hash', password='secret') is False

    with pytest.raises(McAuthPasswordException):
        assert password_hash_is_valid(password_hash='', password='secret') is False

    # Invalid base64
    assert password_hash_is_valid(password_hash=(
        '{SSHA256}ajkdjhdkjashdjkashdkjashdlashdjkashdkjlasdhjasklhdjkashdaskjldhaskjdhalsdjhaslkdhaslkdhaskjdhasldjhas'
        'hjkdashkdjhdkjhakdshjkahdjk'
    ), password='secret') is False

    # Manually generated with Crypt::SaltedHash
    assert password_hash_is_valid(password_hash=(
        '{SSHA256}hddcAPBgxzuWWgs5UtzAjXdAjytpgeP129yCIQWWbel8WLWpj9fN4v/nFmecZd72MPtL4ckI+eYJ9qXfwW+q0ANMJi3qheHBtXkjx'
        'jAkK6KxIo+ZhbkwAS3opq+xVltM'
    ), password='secret') is True

    # Valid hash, invalid password
    assert password_hash_is_valid(password_hash=(
        '{SSHA256}hddcAPBgxzuWWgs5UtzAjXdAjytpgeP129yCIQWWbel8WLWpj9fN4v/nFmecZd72MPtL4ckI+eYJ9qXfwW+q0ANMJi3qheHBtXkjx'
        'jAkK6KxIo+ZhbkwAS3opq+xVltM'
    ), password='invalid_password') is False
    assert password_hash_is_valid(password_hash=(
        '{SSHA256}hddcAPBgxzuWWgs5UtzAjXdAjytpgeP129yCIQWWbel8WLWpj9fN4v/nFmecZd72MPtL4ckI+eYJ9qXfwW+q0ANMJi3qheHBtXkjx'
        'jAkK6KxIo+ZhbkwAS3opq+xVltM'
    ), password='') is False
    with pytest.raises(McAuthPasswordException):
        # noinspection PyTypeChecker
        assert password_hash_is_valid(password_hash=(
            '{SSHA256}hddcAPBgxzuWWgs5UtzAjXdAjytpgeP129yCIQWWbel8WLWpj9fN4v/nFmecZd72MPtL4ckI+eYJ9qXfwW+q0ANMJi3qheHBt'
            'XkjxjAkK6KxIo+ZhbkwAS3opq+xVltM'
        ), password=None) is False

    # No prefix
    with pytest.raises(McAuthPasswordException):
        assert password_hash_is_valid(password_hash=(
            'hddcAPBgxzuWWgs5UtzAjXdAjytpgeP129yCIQWWbel8WLWpj9fN4v/nFmecZd72MPtL4ckI+eYJ9qXfwW+q0ANMJi3qheHBtXkjx'
            'jAkK6KxIo+ZhbkwAS3opq+xVltM'
        ), password='secret') is False

    # Invalid prefix
    with pytest.raises(McAuthPasswordException):
        assert password_hash_is_valid(password_hash=(
            '{SSHA512}hddcAPBgxzuWWgs5UtzAjXdAjytpgeP129yCIQWWbel8WLWpj9fN4v/nFmecZd72MPtL4ckI+eYJ9qXfwW+q0ANMJi3qheHBt'
            'XkjxjAkK6KxIo+ZhbkwAS3opq+xVltM'
        ), password='secret') is False


def test_generate_password_hash():
    salted_hash = generate_password_hash(password='secret')
    assert len(salted_hash) == len((
        '{SSHA256}hddcAPBgxzuWWgs5UtzAjXdAjytpgeP129yCIQWWbel8WLWpj9fN4v/nFmecZd72MPtL4ckI+eYJ9qXfwW+q0ANMJi3qheHBtXkjx'
        'jAkK6KxIo+ZhbkwAS3opq+xVltM'
    ))
    assert salted_hash.startswith('{SSHA256}')

    assert password_hash_is_valid(password='secret', password_hash=salted_hash) is True
    assert password_hash_is_valid(password='invalid_password', password_hash=salted_hash) is False

    # Make sure every salted hash is unique
    assert generate_password_hash(password='secret') != salted_hash


def test_validate_new_password():
    # noinspection PyTypeChecker
    assert len(validate_new_password(email=None, password=None, password_repeat=None)) > 0

    assert len(validate_new_password(email='', password='', password_repeat='')) > 0

    assert len(validate_new_password(email='em@ail.com', password='', password_repeat='')) > 0

    # Passwords do not match
    assert len(validate_new_password(email='em@ail.com', password='abcdefghI', password_repeat='abcdefghX')) > 0

    # Too short
    assert len(validate_new_password(email='em@ail.com', password='abc', password_repeat='abc')) > 0

    too_long_password = random_string(length=200)
    assert len(validate_new_password(email='em@ail.com',
                                     password=too_long_password,
                                     password_repeat=too_long_password)) > 0

    # Email == password
    email = 'abcdef@ghijkl.com'
    assert len(validate_new_password(email=email, password=email, password_repeat=email)) > 0

    # All good
    password = 'correct horse battery staple'
    assert len(validate_new_password(email='abc@def.com',
                                     password=password,
                                     password_repeat=password)) == 0
