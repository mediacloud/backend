from mediawords.db import connect_to_db
from webapp.auth.login import login_with_email_password
from webapp.auth.profile import regenerate_api_key
from webapp.auth.register import add_user
from webapp.auth.user import NewUser


def test_regenerate_api_key():

    db = connect_to_db()

    email = 'test@user.login'
    password = 'userlogin123'
    full_name = 'Test user login'
    ip_address = '1.2.3.4'

    add_user(
        db=db,
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
    user = login_with_email_password(db=db, email=email, password=password, ip_address=ip_address)
    assert user

    before_global_api_key = user.global_api_key()
    assert before_global_api_key

    before_per_ip_api_key = user.api_key_for_ip_address(ip_address=ip_address)
    assert before_per_ip_api_key

    assert before_global_api_key != before_per_ip_api_key

    # Regenerate API key, purge per-IP API keys
    regenerate_api_key(db=db, email=email)

    # Get sample API keys again
    user = login_with_email_password(db=db, email=email, password=password, ip_address=ip_address)
    assert user

    after_global_api_key = user.global_api_key()
    assert after_global_api_key

    after_per_ip_api_key = user.api_key_for_ip_address(ip_address=ip_address)
    assert after_per_ip_api_key

    # Make sure API keys are different
    assert before_global_api_key != after_global_api_key
    assert before_per_ip_api_key != after_per_ip_api_key
