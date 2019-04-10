#!/usr/bin/env py.test

import pytest
import time

from furl import furl

from mediawords.dbi.auth.change_password import (
    change_password,
    change_password_with_old_password,
    McAuthChangePasswordException,
    change_password_with_reset_token,
)
from mediawords.dbi.auth.login import login_with_email_password, McAuthLoginException
from mediawords.dbi.auth.register import add_user
# noinspection PyProtectedMember
from mediawords.dbi.auth.reset_password import _generate_password_reset_token
from mediawords.dbi.auth.user import NewUser, CurrentUser
from mediawords.test.testing_database import TestDatabaseTestCase, TestDoNotSendEmails


class TestChangePassword(TestDatabaseTestCase, TestDoNotSendEmails):

    def test_change_password(self):
        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'

        add_user(
            db=self.db(),
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
        user = login_with_email_password(db=self.db(), email=email, password=password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Change password
        new_password = 'this is a new password to set'
        change_password(
            db=self.db(),
            email=email,
            new_password=new_password,
            new_password_repeat=new_password,
            do_not_inform_via_email=True,
        )

        # Unsuccessful login with old password
        with pytest.raises(McAuthLoginException):
            login_with_email_password(db=self.db(), email=email, password=password)

        # Imposed delay after unsuccessful login
        time.sleep(2)

        # Successful login with new password
        user = login_with_email_password(db=self.db(), email=email, password=new_password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Changing for nonexistent user
        with pytest.raises(McAuthChangePasswordException):
            change_password(
                db=self.db(),
                email='does@not.exist',
                new_password=new_password,
                new_password_repeat=new_password,
                do_not_inform_via_email=True,
            )

        # Passwords don't match
        with pytest.raises(McAuthChangePasswordException):
            change_password(
                db=self.db(),
                email=email,
                new_password='passwords do',
                new_password_repeat='not match',
                do_not_inform_via_email=True,
            )

    def test_change_password_with_old_password(self):
        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'

        add_user(
            db=self.db(),
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
        user = login_with_email_password(db=self.db(), email=email, password=password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Change password
        new_password = 'this is a new password to set'
        change_password_with_old_password(
            db=self.db(),
            email=email,
            old_password=password,
            new_password=new_password,
            new_password_repeat=new_password,
        )

        # Unsuccessful login with old password
        with pytest.raises(McAuthLoginException):
            login_with_email_password(db=self.db(), email=email, password=password)

        # Imposed delay after unsuccessful login
        time.sleep(2)

        # Successful login with new password
        user = login_with_email_password(db=self.db(), email=email, password=new_password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Incorrect password
        with pytest.raises(McAuthChangePasswordException):
            change_password_with_old_password(
                db=self.db(),
                email=email,
                old_password='incorrect password',
                new_password=new_password,
                new_password_repeat=new_password,
            )

        # Changing for nonexistent user
        with pytest.raises(McAuthChangePasswordException):
            even_newer_password = 'abcdef123456'
            change_password_with_old_password(
                db=self.db(),
                email='does@not.exist',
                old_password=new_password,
                new_password=even_newer_password,
                new_password_repeat=even_newer_password,
            )

        # Passwords don't match
        with pytest.raises(McAuthChangePasswordException):
            change_password_with_old_password(
                db=self.db(),
                email=email,
                old_password=new_password,
                new_password='passwords do',
                new_password_repeat='not match',
            )

    def test_change_password_with_reset_token(self):
        # FIXME test changing password for user A using reset token from user B

        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'

        add_user(
            db=self.db(),
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
        user = login_with_email_password(db=self.db(), email=email, password=password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Make sure password reset token is not set
        password_reset_token_hash = self.db().query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert password_reset_token_hash[0] is None

        # Send password reset link
        password_reset_url = 'https://reset-password.com/reset'
        final_password_reset_url = _generate_password_reset_token(
            db=self.db(),
            email=email,
            password_reset_link=password_reset_url,
        )
        assert final_password_reset_url
        assert password_reset_url in final_password_reset_url

        final_password_reset_uri = furl(final_password_reset_url)
        assert final_password_reset_uri.args['email']
        assert final_password_reset_uri.args['password_reset_token']

        # Make sure password reset token is set
        password_reset_token_hash = self.db().query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert password_reset_token_hash[0] is not None

        # Change password
        new_password = 'this is a new password to set'
        change_password_with_reset_token(
            db=self.db(),
            email=email,
            password_reset_token=final_password_reset_uri.args['password_reset_token'],
            new_password=new_password,
            new_password_repeat=new_password,
        )

        # Make sure password reset token has been reset after changing password
        password_reset_token_hash = self.db().query("""
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = %(email)s
        """, {'email': email}).flat()
        assert password_reset_token_hash[0] is None

        # Unsuccessful login with old password
        with pytest.raises(McAuthLoginException):
            login_with_email_password(db=self.db(), email=email, password=password)

        # Imposed delay after unsuccessful login
        time.sleep(2)

        # Successful login with new password
        user = login_with_email_password(db=self.db(), email=email, password=new_password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Incorrect password reset token
        _generate_password_reset_token(
            db=self.db(),
            email=email,
            password_reset_link=password_reset_url,
        )
        with pytest.raises(McAuthChangePasswordException):
            change_password_with_reset_token(
                db=self.db(),
                email=email,
                password_reset_token='incorrect password reset token',
                new_password=new_password,
                new_password_repeat=new_password,
            )

        # Changing for nonexistent user
        final_password_reset_url = _generate_password_reset_token(
            db=self.db(),
            email=email,
            password_reset_link=password_reset_url,
        )
        with pytest.raises(McAuthChangePasswordException):
            change_password_with_reset_token(
                db=self.db(),
                email='does@not.exist',
                password_reset_token=furl(final_password_reset_url).args['password_reset_token'],
                new_password=new_password,
                new_password_repeat=new_password,
            )

        # Passwords don't match
        final_password_reset_url = _generate_password_reset_token(
            db=self.db(),
            email=email,
            password_reset_link=password_reset_url,
        )
        with pytest.raises(McAuthChangePasswordException):
            change_password_with_reset_token(
                db=self.db(),
                email=email,
                password_reset_token=furl(final_password_reset_url).args['password_reset_token'],
                new_password='passwords do',
                new_password_repeat='not match',
            )
