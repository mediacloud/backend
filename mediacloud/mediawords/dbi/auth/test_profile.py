from mediawords.dbi.auth.login import login_with_email_password
from mediawords.dbi.auth.profile import all_users, regenerate_api_key
from mediawords.dbi.auth.register import add_user
from mediawords.dbi.auth.user import NewUser, CurrentUser
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase, TestDoNotSendEmails


class TestProfile(TestDatabaseWithSchemaTestCase, TestDoNotSendEmails):

    def test_all_users(self):
        email = 'test@user.info'
        full_name = 'Test user info'
        notes = 'Test test test'
        weekly_requests_limit = 123
        weekly_requested_items_limit = 456

        add_user(
            db=self.db(),
            new_user=NewUser(
                email=email,
                full_name=full_name,
                notes=notes,
                role_ids=[1],
                active=True,
                password='user_info',
                password_repeat='user_info',
                activation_url='',  # user is active, no need for activation URL
                weekly_requests_limit=weekly_requests_limit,
                weekly_requested_items_limit=weekly_requested_items_limit,
            ),
        )

        users = all_users(db=self.db())
        assert len(users) == 1

        user = users[0]
        assert isinstance(user, CurrentUser)
        assert user.email == email
        assert user.full_name == full_name
        assert user.notes == notes
        assert user.weekly_requests_limit == weekly_requests_limit
        assert user.weekly_requested_items_limit == weekly_requested_items_limit
        assert user.active
        assert user.global_api_key
        assert user.password_hash
        assert user.has_role('admin')

    def test_regenerate_api_key(self):
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

        before_global_api_key = user.global_api_key
        assert before_global_api_key

        before_per_ip_api_key = user.api_key_for_ip_address(ip_address=ip_address)
        assert before_per_ip_api_key

        assert before_global_api_key != before_per_ip_api_key

        # Regenerate API key, purge per-IP API keys
        regenerate_api_key(db=self.db(), email=email)

        # Get sample API keys again
        user = login_with_email_password(db=self.db(), email=email, password=password, ip_address=ip_address)
        assert user

        after_global_api_key = user.global_api_key
        assert after_global_api_key

        after_per_ip_api_key = user.api_key_for_ip_address(ip_address=ip_address)
        assert after_per_ip_api_key

        # Make sure API keys are different
        assert before_global_api_key != after_global_api_key
        assert before_per_ip_api_key != after_per_ip_api_key
