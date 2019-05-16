import pytest

from mediawords.db import connect_to_db
from webapp.auth.info import user_info
from webapp.auth.login import McAuthLoginException, login_with_api_key
from webapp.auth.register import add_user
from webapp.auth.user import NewUser


def test_login_with_api_key_inactive_user():
    """Inactive user logging in with API key."""

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
            active=False,
            password=password,
            password_repeat=password,
            activation_url='https://activate.com/activate',
        ),
    )

    user = user_info(db=db, email=email)
    assert user
    global_api_key = user.global_api_key()

    with pytest.raises(McAuthLoginException) as ex:
        login_with_api_key(db=db, api_key=global_api_key, ip_address=ip_address)

    # Make sure the error message explicitly states that login failed due to user not being active
    assert 'not active' in str(ex)
