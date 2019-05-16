from mediawords.db import connect_to_db
from webapp.auth.profile import all_users
from webapp.auth.register import add_user
from webapp.auth.user import NewUser, CurrentUser


def test_all_users():
    db = connect_to_db()

    email = 'test@user.info'
    full_name = 'Test user info'
    notes = 'Test test test'
    weekly_requests_limit = 123
    weekly_requested_items_limit = 456

    add_user(
        db=db,
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

    users = all_users(db=db)
    assert len(users) == 1

    user = users[0]
    assert isinstance(user, CurrentUser)
    assert user.email() == email
    assert user.full_name() == full_name
    assert user.notes() == notes
    assert user.weekly_requests_limit() == weekly_requests_limit
    assert user.weekly_requested_items_limit() == weekly_requested_items_limit
    assert user.active()
    assert user.global_api_key()
    assert user.password_hash()
    assert user.has_role('admin')
