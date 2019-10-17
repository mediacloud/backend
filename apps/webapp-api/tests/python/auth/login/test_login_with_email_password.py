import time

import pytest

from mediawords.db import connect_to_db
from webapp.auth.login import login_with_email_password, McAuthLoginException
from webapp.auth.register import add_user
from webapp.auth.user import NewUser, CurrentUser


def test_login_with_email_password():
    db = connect_to_db()

    email = 'test@user.login'
    password = 'userlogin123'
    full_name = 'Test user login'

    add_user(
        db=db,
        new_user=NewUser(
            email=email,
            full_name=full_name,
            has_consented=True,
            notes='Test test test',
            role_ids=[1],
            active=True,
            password=password,
            password_repeat=password,
            activation_url='',  # user is active, no need for activation URL
        ),
    )

    # Successful login
    user = login_with_email_password(db=db, email=email, password=password)
    assert user
    assert isinstance(user, CurrentUser)
    assert user.email() == email
    assert user.full_name() == full_name

    # Unsuccessful login
    with pytest.raises(McAuthLoginException):
        login_with_email_password(db=db, email=email, password='wrong password')

    # Subsequent login attempt after a failed one should be delayed by 1 second
    with pytest.raises(McAuthLoginException):
        login_with_email_password(db=db, email=email, password=password)

    # Successful login after waiting out the delay
    time.sleep(2)
    user = login_with_email_password(db=db, email=email, password=password)
    assert user
    assert isinstance(user, CurrentUser)
    assert user.email() == email
    assert user.full_name() == full_name
