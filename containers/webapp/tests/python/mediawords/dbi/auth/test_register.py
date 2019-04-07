import time

import pytest
from furl import furl

from mediawords.dbi.auth.login import login_with_email_password, McAuthLoginException
# noinspection PyProtectedMember
from mediawords.dbi.auth.register import (
    add_user,
    activate_user_via_token,
    send_user_activation_token,
    _generate_user_activation_token,
    McAuthRegisterException,
)
from mediawords.dbi.auth.user import NewUser, CurrentUser, McAuthUserException
from mediawords.test.testing_database import TestDatabaseTestCase, TestDoNotSendEmails


class TestRegister(TestDatabaseTestCase, TestDoNotSendEmails):

    def test_add_user(self):
        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'

        new_user = NewUser(
            email=email,
            full_name=full_name,
            notes='Test test test',
            role_ids=[1],
            active=True,
            password=password,
            password_repeat=password,
            activation_url='',  # user is active, no need for activation URL
        )

        # Add user
        add_user(db=self.db(), new_user=new_user)

        # Test logging in
        user = login_with_email_password(db=self.db(), email=email, password=password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Faulty input
        with pytest.raises(McAuthRegisterException):
            # noinspection PyTypeChecker
            add_user(db=self.db(), new_user=None)

        # Existing user
        with pytest.raises(McAuthRegisterException):
            add_user(db=self.db(), new_user=new_user)

        # Existing user with uppercase email
        with pytest.raises(McAuthRegisterException):
            add_user(
                db=self.db(),
                new_user=NewUser(
                    email=email.upper(),
                    full_name=full_name,
                    notes='Test test test',
                    role_ids=[1],
                    active=True,
                    password=password,
                    password_repeat=password,
                    activation_url='',  # user is active, no need for activation URL
                ),
            )

        # Invalid password
        with pytest.raises(McAuthUserException):
            add_user(
                db=self.db(),
                new_user=NewUser(
                    email='user123@email.com',
                    full_name=full_name,
                    notes='Test test test',
                    role_ids=[1],
                    active=True,
                    password='abc',
                    password_repeat='def',
                    activation_url='',  # user is active, no need for activation URL
                ),
            )

        # Nonexistent roles
        with pytest.raises(McAuthRegisterException):
            add_user(
                db=self.db(),
                new_user=NewUser(
                    email='user456@email.com',
                    full_name=full_name,
                    notes='Test test test',
                    role_ids=[42],
                    active=True,
                    password=password,
                    password_repeat=password,
                    activation_url='',  # user is active, no need for activation URL
                ),
            )

        # Both the user is set as active and the activation URL is set
        with pytest.raises(McAuthUserException):
            add_user(
                db=self.db(),
                new_user=NewUser(
                    email='user789@email.com',
                    full_name=full_name,
                    notes='Test test test',
                    role_ids=[1],
                    active=True,
                    password=password,
                    password_repeat=password,
                    activation_url='https://activate-user.com/activate',
                ),
            )

        # User is neither active not the activation URL is set
        with pytest.raises(McAuthUserException):
            add_user(
                db=self.db(),
                new_user=NewUser(
                    email='user784932@email.com',
                    full_name=full_name,
                    notes='Test test test',
                    role_ids=[1],
                    active=False,
                    password=password,
                    password_repeat=password,
                    activation_url='',
                ),
            )

    def test_activate_user_via_token(self):
        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'
        activation_url = 'https://activate.com/activate'

        # Add inactive user
        add_user(
            db=self.db(),
            new_user=NewUser(
                email=email,
                full_name=full_name,
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
            login_with_email_password(db=self.db(), email=email, password=password)

        # Make sure the error message explicitly states that login failed due to user not being active
        assert 'not active' in str(ex)

        # Make sure activation token is set
        activation_token_hash = self.db().query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert activation_token_hash
        assert len(activation_token_hash) == 1
        assert len(activation_token_hash[0]) > 0

        # Send password reset link
        final_activation_url = _generate_user_activation_token(
            db=self.db(),
            email=email,
            activation_link=activation_url,
        )
        final_activation_uri = furl(final_activation_url)
        assert final_activation_uri.args['email']

        activation_token = final_activation_uri.args['activation_token']
        assert activation_token

        # Make sure activation token is (still) set
        activation_token_hash = self.db().query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert activation_token_hash
        assert len(activation_token_hash) == 1
        assert len(activation_token_hash[0]) > 0

        # Activate user
        activate_user_via_token(db=self.db(), email=email, activation_token=activation_token)

        # Imposed delay after unsuccessful login
        time.sleep(2)

        # Test logging in
        user = login_with_email_password(db=self.db(), email=email, password=password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Make sure activation token is not set anymore
        activation_token_hash = self.db().query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert activation_token_hash
        assert len(activation_token_hash) == 1
        assert activation_token_hash[0] is None

        # Incorrect activation token
        _generate_user_activation_token(db=self.db(), email=email, activation_link=activation_url)
        with pytest.raises(McAuthRegisterException):
            activate_user_via_token(db=self.db(), email=email, activation_token='incorrect activation token')

        # Activating nonexistent user
        final_activation_url = _generate_user_activation_token(
            db=self.db(),
            email=email,
            activation_link=activation_url,
        )
        final_activation_uri = furl(final_activation_url)
        activation_token = final_activation_uri.args['activation_token']
        with pytest.raises(McAuthRegisterException):
            activate_user_via_token(db=self.db(), email='does@not.exist', activation_token=activation_token)

        # FIXME test activating existing users with a activation token which is not theirs

    def test_send_user_activation_token(self):
        email = 'test@user.login'
        password = 'userlogin123'
        activation_url = 'http://activate.com/'
        subscribe_to_newsletter = True

        add_user(
            db=self.db(),
            new_user=NewUser(
                email=email,
                full_name='Test user login',
                notes='Test test test',
                role_ids=[1],
                active=True,
                password=password,
                password_repeat=password,
                activation_url='',  # user is active, no need for activation URL
                subscribe_to_newsletter=subscribe_to_newsletter,
            ),
        )

        # Existing user
        send_user_activation_token(
            db=self.db(),
            email=email,
            activation_link=activation_url,
            subscribe_to_newsletter=subscribe_to_newsletter,
        )

        # Nonexistent user (call shouldn't fail because we don't want to reveal which users are in the system so we
        # pretend that we've sent the email)
        send_user_activation_token(
            db=self.db(),
            email='does@not.exist',
            activation_link=activation_url,
            subscribe_to_newsletter=subscribe_to_newsletter,
        )
