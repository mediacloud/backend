import pytest

from mediawords.db import connect_to_db
from webapp.auth.login import login_with_email_password
from webapp.auth.register import add_user, McAuthRegisterException
from webapp.auth.user import NewUser, CurrentUser, McAuthUserException
from webapp.test.dummy_emails import TestDoNotSendEmails


class AddUserTestCase(TestDoNotSendEmails):
    
    def test_add_user(self):
        db = connect_to_db()

        email = 'test@user.login'
        password = 'userlogin123'
        full_name = 'Test user login'

        new_user = NewUser(
            email=email,
            full_name=full_name,
            has_consented=True,
            notes='Test test test',
            role_ids=[1],
            active=True,
            password=password,
            password_repeat=password,
            activation_url='',  # user is active, no need for activation URL
        )

        # Add user
        add_user(db=db, new_user=new_user)

        # Test logging in
        user = login_with_email_password(db=db, email=email, password=password)
        assert user
        assert isinstance(user, CurrentUser)
        assert user.email() == email
        assert user.full_name() == full_name

        # Faulty input
        with pytest.raises(McAuthRegisterException):
            # noinspection PyTypeChecker
            add_user(db=db, new_user=None)

        # Existing user
        with pytest.raises(McAuthRegisterException):
            add_user(db=db, new_user=new_user)

        # Existing user with uppercase email
        with pytest.raises(McAuthRegisterException):
            add_user(
                db=db,
                new_user=NewUser(
                    email=email.upper(),
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

        # Invalid password
        with pytest.raises(McAuthUserException):
            add_user(
                db=db,
                new_user=NewUser(
                    email='user123@email.com',
                    full_name=full_name,
                    has_consented=True,
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
                db=db,
                new_user=NewUser(
                    email='user456@email.com',
                    full_name=full_name,
                    has_consented=True,
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
                db=db,
                new_user=NewUser(
                    email='user789@email.com',
                    full_name=full_name,
                    has_consented=True,
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
                db=db,
                new_user=NewUser(
                    email='user784932@email.com',
                    full_name=full_name,
                    has_consented=True,
                    notes='Test test test',
                    role_ids=[1],
                    active=False,
                    password=password,
                    password_repeat=password,
                    activation_url='',
                ),
            )
