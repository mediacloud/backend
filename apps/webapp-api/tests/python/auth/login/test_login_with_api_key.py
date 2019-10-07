import pytest

from mediawords.db import connect_to_db
from webapp.auth.login import login_with_email_password, McAuthLoginException, login_with_api_key
from webapp.auth.register import add_user
from webapp.auth.user import NewUser


def test_login_with_api_key():
    db = connect_to_db()

    email = 'test@user.login'
    password = 'userlogin123'
    full_name = 'Test user login'
    ip_address = '1.2.3.4'

    add_user(
        db=db,
        new_user=NewUser(
            email=email,
            full_name=full_name,
            notes='Test test test',
            role_ids=[1],
            active=True,
            password=password,
            password_repeat=password,
            activation_url='',  # user is active, no need for activation URL
        ),
    )

    # Get sample API keys
    user = login_with_email_password(db=db, email=email, password=password, ip_address=ip_address)
    assert user

    global_api_key = user.global_api_key()
    assert global_api_key

    per_ip_api_key = user.api_key_for_ip_address(ip_address=ip_address)
    assert per_ip_api_key

    assert global_api_key != per_ip_api_key

    # Non-existent API key
    with pytest.raises(McAuthLoginException):
        login_with_api_key(db=db, api_key='Non-existent API key', ip_address=ip_address)

    # Global API key
    user = login_with_api_key(db=db, api_key=global_api_key, ip_address=ip_address)
    assert user
    assert user.email() == email
    assert user.global_api_key() == global_api_key

    # Per-IP API key
    user = login_with_api_key(db=db, api_key=per_ip_api_key, ip_address=ip_address)
    assert user
    assert user.email() == email

    # FIXME test logging in with per-IP API key from a wrong IP address
