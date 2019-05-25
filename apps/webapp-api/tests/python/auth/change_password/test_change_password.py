import time

import pytest

from mediawords.db import connect_to_db
from webapp.auth.change_password import change_password, McAuthChangePasswordException
from webapp.auth.login import login_with_email_password, McAuthLoginException
from webapp.auth.register import add_user
from webapp.auth.user import NewUser, CurrentUser


def test_change_password():
    db = connect_to_db()

    email = 'test@user.login'
    password = 'userlogin123'
    full_name = 'Test user login'

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

    # Successful login
    user = login_with_email_password(db=db, email=email, password=password)
    assert user
    assert isinstance(user, CurrentUser)
    assert user.email() == email
    assert user.full_name() == full_name

    # Change password
    new_password = 'this is a new password to set'
    change_password(
        db=db,
        email=email,
        new_password=new_password,
        new_password_repeat=new_password,
        do_not_inform_via_email=True,
    )

    # Unsuccessful login with old password
    with pytest.raises(McAuthLoginException):
        login_with_email_password(db=db, email=email, password=password)

    # Imposed delay after unsuccessful login
    time.sleep(2)

    # Successful login with new password
    user = login_with_email_password(db=db, email=email, password=new_password)
    assert user
    assert isinstance(user, CurrentUser)
    assert user.email() == email
    assert user.full_name() == full_name

    # Changing for nonexistent user
    with pytest.raises(McAuthChangePasswordException):
        change_password(
            db=db,
            email='does@not.exist',
            new_password=new_password,
            new_password_repeat=new_password,
            do_not_inform_via_email=True,
        )

    # Passwords don't match
    with pytest.raises(McAuthChangePasswordException):
        change_password(
            db=db,
            email=email,
            new_password='passwords do',
            new_password_repeat='not match',
            do_not_inform_via_email=True,
        )
