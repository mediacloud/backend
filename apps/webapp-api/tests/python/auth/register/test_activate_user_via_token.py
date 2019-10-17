import time

import pytest
from furl import furl

from mediawords.db import connect_to_db
from webapp.auth.login import McAuthLoginException, login_with_email_password
# noinspection PyProtectedMember
from webapp.auth.register import (
    add_user,
    _generate_user_activation_token,
    activate_user_via_token,
    McAuthRegisterException,
)
from webapp.auth.user import NewUser, CurrentUser
from webapp.test.dummy_emails import TestDoNotSendEmails


class ActivateUserViaTokenTestCase(TestDoNotSendEmails):

    def test_activate_user_via_token(self):
        db = connect_to_db()

        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'
        activation_url = 'https://activate.com/activate'

        # Add inactive user
        add_user(
            db=db,
            new_user=NewUser(
                email=email,
                full_name=full_name,
                has_consented=True,
                notes='Test test test',
                role_ids=[1],
                active=False,  # not active, needs to be activated
                password=password,
                password_repeat=password,
                activation_url=activation_url,
            ),
        )

        # Test logging in
        with pytest.raises(McAuthLoginException) as ex:
            login_with_email_password(db=db, email=email, password=password)

        # Make sure the error message explicitly states that login failed due to user not being active
        assert 'not active' in str(ex)

        # Make sure activation token is set
        activation_token_hash = db.query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert activation_token_hash
        assert len(activation_token_hash) == 1
        assert len(activation_token_hash[0]) > 0

        # Send password reset link
        final_activation_url = _generate_user_activation_token(
            db=db,
            email=email,
            activation_link=activation_url,
        )
        final_activation_uri = furl(final_activation_url)
        assert final_activation_uri.args['email']

        activation_token = final_activation_uri.args['activation_token']
        assert activation_token

        # Make sure activation token is (still) set
        activation_token_hash = db.query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert activation_token_hash
        assert len(activation_token_hash) == 1
        assert len(activation_token_hash[0]) > 0

        # Activate user
        activate_user_via_token(db=db, email=email, activation_token=activation_token)

        # Imposed delay after unsuccessful login
        time.sleep(2)

        # Test logging in
        user = login_with_email_password(db=db, email=email, password=password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Make sure activation token is not set anymore
        activation_token_hash = db.query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert activation_token_hash
        assert len(activation_token_hash) == 1
        assert activation_token_hash[0] is None

        # Incorrect activation token
        _generate_user_activation_token(db=db, email=email, activation_link=activation_url)
        with pytest.raises(McAuthRegisterException):
            activate_user_via_token(db=db, email=email, activation_token='incorrect activation token')

        # Activating nonexistent user
        final_activation_url = _generate_user_activation_token(
            db=db,
            email=email,
            activation_link=activation_url,
        )
        final_activation_uri = furl(final_activation_url)
        activation_token = final_activation_uri.args['activation_token']
        with pytest.raises(McAuthRegisterException):
            activate_user_via_token(db=db, email='does@not.exist', activation_token=activation_token)

        # FIXME test activating existing users with a activation token which is not theirs
