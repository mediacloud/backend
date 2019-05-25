from mediawords.db import connect_to_db
from webapp.auth.register import add_user, send_user_activation_token
from webapp.auth.user import NewUser
from webapp.test.dummy_emails import TestDoNotSendEmails


class SendUserActivationTokenTestCase(TestDoNotSendEmails):

    def test_send_user_activation_token(self):

        db = connect_to_db()

        email = 'test@user.login'
        password = 'userlogin123'
        activation_url = 'http://activate.com/'
        subscribe_to_newsletter = True

        add_user(
            db=db,
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
            db=db,
            email=email,
            activation_link=activation_url,
            subscribe_to_newsletter=subscribe_to_newsletter,
        )

        # Nonexistent user (call shouldn't fail because we don't want to reveal which users are in the system so we
        # pretend that we've sent the email)
        send_user_activation_token(
            db=db,
            email='does@not.exist',
            activation_link=activation_url,
            subscribe_to_newsletter=subscribe_to_newsletter,
        )
