from mediawords.dbi.auth.register import add_user
from mediawords.dbi.auth.reset_password import send_password_reset_token
from mediawords.dbi.auth.user import NewUser
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase, TestDoNotSendEmails


class TestResetPassword(TestDatabaseWithSchemaTestCase, TestDoNotSendEmails):

    def test_send_password_reset_token(self):
        email = 'test@user.login'
        password = 'userlogin123'
        password_reset_link = 'http://password-reset.com/'

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
            ),
        )

        # Existing user
        send_password_reset_token(db=self.db(), email=email, password_reset_link=password_reset_link)

        # Nonexisting user (call shouldn't fail because we don't want to reveal which users are in the system so we
        # pretend that we've sent the email)
        send_password_reset_token(db=self.db(), email='does@not.exist', password_reset_link=password_reset_link)
