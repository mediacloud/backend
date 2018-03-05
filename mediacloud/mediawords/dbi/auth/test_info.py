from mediawords.dbi.auth.info import user_info
from mediawords.dbi.auth.register import add_user
from mediawords.dbi.auth.user import NewUser, CurrentUser
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase, TestDoNotSendEmails


class TestInfo(TestDatabaseWithSchemaTestCase, TestDoNotSendEmails):

    def test_user_info(self):
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

        user = user_info(db=self.db(), email=email)

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
