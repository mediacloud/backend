from typing import List, Optional

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.mail import send_email
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.text import random_string
from webapp.auth.change_password import change_password
from webapp.auth.info import user_info
from webapp.auth.password import generate_secure_hash
from webapp.auth.user import CurrentUser, ModifyUser
from webapp.mail.messages import AuthAPIKeyResetMessage

log = create_logger(__name__)


class McAuthProfileException(Exception):
    """Authentication profile exception."""
    pass


def all_users(db: DatabaseHandler) -> List[CurrentUser]:
    """Fetch and return a list of users and their roles."""

    # Start a transaction so that the list of users doesn't change while we run separate queries with user_info()
    db.begin()

    user_emails = db.query("""
        SELECT email
        FROM auth_users
        ORDER BY auth_users_id
    """).flat()

    users = []

    for email in user_emails:
        users.append(user_info(db=db, email=email))

    db.commit()

    return users


def update_user(db: DatabaseHandler, user_updates: ModifyUser) -> None:
    """Update an existing user."""

    if not user_updates:
        raise McAuthProfileException("Existing user is undefined.")

    # Check if user exists
    try:
        user = user_info(db=db, email=user_updates.email())
    except Exception:
        raise McAuthProfileException('User with email address "%s" does not exist.' % user_updates.email())

    db.begin()

    if user_updates.full_name() is not None:
        db.query("""
            UPDATE auth_users
            SET full_name = %(full_name)s
            WHERE email = %(email)s
        """, {
            'full_name': user_updates.full_name(),
            'email': user_updates.email(),
        })

    if user_updates.notes() is not None:
        db.query("""
            UPDATE auth_users
            SET notes = %(notes)s
            WHERE email = %(email)s
        """, {
            'notes': user_updates.notes(),
            'email': user_updates.email(),
        })

    if user_updates.active() is not None:
        db.query("""
            UPDATE auth_users
            SET active = %(active)s
            WHERE email = %(email)s
        """, {
            'active': bool(int(user_updates.active())),
            'email': user_updates.email(),
        })

    if user_updates.password() is not None:
        try:
            change_password(
                db=db,
                email=user_updates.email(),
                new_password=user_updates.password(),
                new_password_repeat=user_updates.password_repeat(),
                do_not_inform_via_email=True,
            )
        except Exception as ex:
            db.rollback()
            raise McAuthProfileException("Unable to change password: %s" % str(ex))

    if user_updates.weekly_requests_limit() is not None:
        db.query("""
            UPDATE auth_user_limits
            SET weekly_requests_limit = %(weekly_requests_limit)s
            WHERE auth_users_id = %(auth_users_id)s
        """, {
            'weekly_requests_limit': user_updates.weekly_requests_limit(),
            'auth_users_id': user.user_id(),
        })

    if user_updates.weekly_requested_items_limit() is not None:
        db.query("""
            UPDATE auth_user_limits
            SET weekly_requested_items_limit = %(weekly_requested_items_limit)s
            WHERE auth_users_id = %(auth_users_id)s
        """, {
            'weekly_requested_items_limit': user_updates.weekly_requested_items_limit(),
            'auth_users_id': user.user_id(),
        })

    if user_updates.role_ids() is not None:
        db.query("""
            DELETE FROM auth_users_roles_map
            WHERE auth_users_id = %(auth_users_id)s
        """, {'auth_users_id': user.user_id()})

        for auth_roles_id in user_updates.role_ids():
            db.insert(table='auth_users_roles_map', insert_hash={
                'auth_users_id': user.user_id(),
                'auth_roles_id': auth_roles_id,
            })

    db.commit()


def delete_user(db: DatabaseHandler, email: str) -> None:
    """Delete user."""

    email = decode_object_from_bytes_if_needed(email)

    if not email:
        raise McAuthProfileException('Email address is empty.')

    # Check if user exists
    try:
        user_info(db=db, email=email)
    except Exception:
        raise McAuthProfileException("User with email address '%s' does not exist." % email)

    # Delete the user (PostgreSQL's relation will take care of 'auth_users_roles_map')
    db.query("""
        DELETE FROM auth_users
        WHERE email = %(email)s
    """, {'email': email})


def regenerate_api_key(db: DatabaseHandler, email: str) -> None:
    """Regenerate API key -- creates new non-IP limited API key, removes all IP-limited API keys."""

    email = decode_object_from_bytes_if_needed(email)

    if not email:
        raise McAuthProfileException('Email address is empty.')

    # Check if user exists
    try:
        user = user_info(db=db, email=email)
    except Exception:
        raise McAuthProfileException("User with email address '%s' does not exist." % email)

    db.begin()

    # Purge all IP-limited API keys
    db.query("""
        DELETE FROM auth_user_api_keys
        WHERE ip_address IS NOT NULL
          AND auth_users_id = (
            SELECT auth_users_id
            FROM auth_users
            WHERE email = %(email)s
          )
    """, {'email': email})

    # Regenerate non-IP limited API key
    db.query("""
        UPDATE auth_user_api_keys

        -- DEFAULT points to a generation function
        SET api_key = DEFAULT

        WHERE ip_address IS NULL
          AND auth_users_id = (
            SELECT auth_users_id
            FROM auth_users
            WHERE email = %(email)s
          )
    """, {'email': email})

    message = AuthAPIKeyResetMessage(to=email, full_name=user.full_name())
    if not send_email(message):
        db.rollback()
        raise McAuthProfileException("Unable to send email about reset API key.")

    db.commit()


def create_password_reset_token(db: DatabaseHandler, email: str) -> Optional[str]:
    """Generate password reset token used for both activating newly registered users and resetting passwords.

    Returns non-hashed password reset token or None if user was not found.
    """

    email = decode_object_from_bytes_if_needed(email)

    if not email:
        raise McAuthProfileException('Email address is empty.')

    # Check if the email address exists in the user table; if not, pretend that we sent the activation link with a
    # "success" message. That way the adversary would not be able to find out which email addresses are active users.
    #
    # (Possible improvement: make the script work for the exact same amount of time in both cases to avoid timing
    # attacks)
    user_exists = db.query("""
        SELECT auth_users_id,
               email
        FROM auth_users
        WHERE email = %(email)s
        LIMIT 1
    """, {'email': email}).hash()
    if user_exists is None or len(user_exists) == 0:
        # User was not found, so set the email address to an empty string, but don't return just now and continue with a
        # rather slowish process of generating a activation token (in order to reduce the risk of timing attacks)
        email = ''

    # Generate the activation token
    password_reset_token = random_string(length=64)
    if len(password_reset_token) == 0:
        raise McAuthProfileException('Unable to generate an activation token.')

    # Hash + validate the activation token
    password_reset_token_hash = generate_secure_hash(password=password_reset_token)
    if not password_reset_token_hash:
        raise McAuthProfileException("Unable to hash an activation token.")

    # Set the activation token hash in the database (if the email address doesn't exist, this query will do nothing)
    db.query("""
        UPDATE auth_users
        SET password_reset_token_hash = %(password_reset_token_hash)s
        WHERE email = %(email)s
          AND email != ''
    """, {
        'email': email,
        'password_reset_token_hash': password_reset_token_hash,
    })

    return password_reset_token
