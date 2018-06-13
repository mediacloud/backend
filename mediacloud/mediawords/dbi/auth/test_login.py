import pytest
import time

from mediawords.dbi.auth.login import login_with_email_password, McAuthLoginException, login_with_api_key
from mediawords.dbi.auth.profile import user_info
from mediawords.dbi.auth.register import add_user
from mediawords.dbi.auth.user import NewUser, CurrentUser
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase, TestDoNotSendEmails


class TestLogin(TestDatabaseWithSchemaTestCase, TestDoNotSendEmails):

    def test_login_with_email_password(self):
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

        # Unsuccessful login
        with pytest.raises(McAuthLoginException):
            login_with_email_password(db=self.db(), email=email, password='wrong password')

        # Subsequent login attempt after a failed one should be delayed by 1 second
        with pytest.raises(McAuthLoginException):
            login_with_email_password(db=self.db(), email=email, password=password)

        # Successful login after waiting out the delay
        time.sleep(2)
        user = login_with_email_password(db=self.db(), email=email, password=password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

    def test_login_with_email_password_inactive_user(self):
        """Inactive user logging in with username and password."""

        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'

        # Inactive user
        add_user(
            db=self.db(),
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
            login_with_email_password(db=self.db(), email=email, password=password)

        # Make sure the error message explicitly states that login failed due to user not being active
        assert 'not active' in str(ex)

    def test_login_with_api_key(self):
        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'
        ip_address = '1.2.3.4'

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

        # Get sample API keys
        user = login_with_email_password(db=self.db(), email=email, password=password, ip_address=ip_address)
        assert user

        global_api_key = user.global_api_key()
        assert global_api_key

        per_ip_api_key = user.api_key_for_ip_address(ip_address=ip_address)
        assert per_ip_api_key

        assert global_api_key != per_ip_api_key

        # Non-existent API key
        with pytest.raises(McAuthLoginException):
            login_with_api_key(db=self.db(), api_key='Non-existent API key', ip_address=ip_address)

        # Global API key
        user = login_with_api_key(db=self.db(), api_key=global_api_key, ip_address=ip_address)
        assert user
        assert user.email() == email
        assert user.global_api_key() == global_api_key

        # Per-IP API key
        user = login_with_api_key(db=self.db(), api_key=per_ip_api_key, ip_address=ip_address)
        assert user
        assert user.email() == email

        # FIXME test logging in with per-IP API key from a wrong IP address

    def test_login_with_api_key_inactive_user(self):
        """Inactive user logging in with API key."""

        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'
        ip_address = '1.2.3.4'

        add_user(
            db=self.db(),
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

        user = user_info(db=self.db(), email=email)
        assert user
        global_api_key = user.global_api_key()

        with pytest.raises(McAuthLoginException) as ex:
            login_with_api_key(db=self.db(), api_key=global_api_key, ip_address=ip_address)

        # Make sure the error message explicitly states that login failed due to user not being active
        assert 'not active' in str(ex)
