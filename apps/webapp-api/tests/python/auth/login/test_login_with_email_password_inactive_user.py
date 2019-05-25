import pytest

from mediawords.db import connect_to_db
from webapp.auth.login import McAuthLoginException, login_with_email_password
from webapp.auth.register import add_user
from webapp.auth.user import NewUser
from webapp.test.dummy_emails import TestDoNotSendEmails


class LoginWithEmailPasswordInactiveUserTestCase(TestDoNotSendEmails):

    def test_login_with_email_password_inactive_user(self):
        """Inactive user logging in with username and password."""

        db = connect_to_db()

        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'

        # Inactive user
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

        with pytest.raises(McAuthLoginException) as ex:
            login_with_email_password(db=db, email=email, password=password)

        # Make sure the error message explicitly states that login failed due to user not being active
        assert 'not active' in str(ex)
