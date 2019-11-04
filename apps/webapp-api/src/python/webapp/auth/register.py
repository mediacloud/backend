from typing import Optional

from furl import furl

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.mail import send_email
from mediawords.util.perl import decode_object_from_bytes_if_needed
from webapp.auth.info import user_info
from webapp.auth.password import generate_secure_hash, password_reset_token_is_valid
from webapp.auth.profile import create_password_reset_token
from webapp.auth.user import NewUser
from webapp.mail.messages import AuthActivationNeededMessage, AuthActivatedMessage

log = create_logger(__name__)


class McAuthRegisterException(Exception):
    """User registration exception."""
    pass


# Kept in a separate subroutine for easier testing.
def _generate_user_activation_token(db: DatabaseHandler, email: str, activation_link: str) -> Optional[str]:
    """Generate user activation token; returns None if user was not found."""

    email = decode_object_from_bytes_if_needed(email)
    activation_link = decode_object_from_bytes_if_needed(activation_link)

    if not email:
        raise McAuthRegisterException('Email address is empty.')

    if not activation_link:
        raise McAuthRegisterException('Activation link is empty.')

    activation_token = create_password_reset_token(db=db, email=email)
    if len(activation_token) == 0:
        return None

    url = furl(activation_link)
    url.args['email'] = email
    url.args['activation_token'] = activation_token
    return str(url.url)


def send_user_activation_token(db: DatabaseHandler,
                               email: str,
                               activation_link: str) -> None:
    """Prepare for activation by emailing the activation token."""

    email = decode_object_from_bytes_if_needed(email)
    activation_link = decode_object_from_bytes_if_needed(activation_link)

    # Check if user exists
    try:
        user = user_info(db=db, email=email)
        full_name = user.full_name()

    except Exception as ex:
        log.warning("Unable to fetch user profile for user '%s': %s" % (email, str(ex),))
        full_name = 'Nonexistent user'

    # If user was not found, send an email to a random address anyway to avoid timing attack
    full_activation_link = _generate_user_activation_token(db=db, email=email, activation_link=activation_link)
    if not full_activation_link:
        log.warning("Unable to generate full activation link for email '%s'" % email)
        email = 'nowhere@mediacloud.org'
        full_activation_link = 'activation link'

    message = AuthActivationNeededMessage(
        to=email,
        full_name=full_name,
        activation_url=full_activation_link,
    )
    if not send_email(message):
        raise McAuthRegisterException('The user was created, but I was unable to send you an activation email.')


def add_user(db: DatabaseHandler, new_user: NewUser) -> None:
    """Add new user."""

    if not new_user:
        raise McAuthRegisterException("New user is undefined.")

    # Check if user already exists
    user_exists = db.query("""
        SELECT auth_users_id
        FROM auth_users
        WHERE email = %(email)s
        LIMIT 1
    """, {'email': new_user.email()}).hash()

    if user_exists is not None and 'auth_users_id' in user_exists:
        raise McAuthRegisterException("User with email '%s' already exists." % new_user.email())

    # Hash + validate the password
    try:
        password_hash = generate_secure_hash(password=new_user.password())
        if not password_hash:
            raise McAuthRegisterException("Password hash is empty.")
    except Exception as ex:
        log.error("Unable to hash a new password: {}".format(ex))
        raise McAuthRegisterException('Unable to hash a new password.')

    db.begin()

    # Create the user
    db.create(
        table='auth_users',
        insert_hash={
            'email': new_user.email(),
            'password_hash': password_hash,
            'full_name': new_user.full_name(),
            'notes': new_user.notes(),
            'active': bool(int(new_user.active())),
            'has_consented': bool(int(new_user.has_consented())),
        }
    )

    # Fetch the user's ID
    try:
        user = user_info(db=db, email=new_user.email())
    except Exception as ex:
        db.rollback()
        raise McAuthRegisterException("I've attempted to create the user but it doesn't exist: %s" % str(ex))

    # Create roles
    try:
        for auth_roles_id in new_user.role_ids():
            db.create(table='auth_users_roles_map', insert_hash={
                'auth_users_id': user.user_id(),
                'auth_roles_id': auth_roles_id,
            })
    except Exception as ex:
        raise McAuthRegisterException("Unable to create roles: %s" % str(ex))

    # Update limits (if they're defined)
    resource_limits = new_user.resource_limits()
    if resource_limits:

        if resource_limits.weekly_requests() is not None:
            db.query("""
                UPDATE auth_user_limits
                SET weekly_requests_limit = %(weekly_requests_limit)s
                WHERE auth_users_id = %(auth_users_id)s
            """, {
                'auth_users_id': user.user_id(),
                'weekly_requests_limit': resource_limits.weekly_requests(),
            })

        if resource_limits.weekly_requested_items() is not None:
            db.query("""
                UPDATE auth_user_limits
                SET weekly_requested_items_limit = %(weekly_requested_items_limit)s
                WHERE auth_users_id = %(auth_users_id)s
            """, {
                'auth_users_id': user.user_id(),
                'weekly_requested_items_limit': resource_limits.weekly_requested_items(),
            })

        if resource_limits.max_topic_stories() is not None:
            db.query("""
                UPDATE auth_user_limits
                SET max_topic_stories = %(max_topic_stories)s
                WHERE auth_users_id = %(auth_users_id)s
            """, {
                'auth_users_id': user.user_id(),
                'max_topic_stories': resource_limits.max_topic_stories(),
            })

    if not new_user.active():
        send_user_activation_token(
            db=db,
            email=new_user.email(),
            activation_link=new_user.activation_url(),
        )

    db.commit()


def activate_user_via_token(db: DatabaseHandler, email: str, activation_token: str) -> None:
    """Change password with a password token sent by email."""

    email = decode_object_from_bytes_if_needed(email)
    activation_token = decode_object_from_bytes_if_needed(activation_token)

    if not email:
        raise McAuthRegisterException("Email is empty.")
    if not activation_token:
        raise McAuthRegisterException('Password reset token is empty.')

    # Validate the token once more (was pre-validated in controller)
    if not password_reset_token_is_valid(db=db, email=email, password_reset_token=activation_token):
        raise McAuthRegisterException('Activation token is invalid.')

    db.begin()

    # Set the password hash
    db.query("""
        UPDATE auth_users
        SET active = TRUE
        WHERE email = %(email)s
    """, {'email': email})

    # Unset the password reset token
    db.query("""
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = %(email)s
    """, {'email': email})

    user = user_info(db=db, email=email)

    message = AuthActivatedMessage(to=email, full_name=user.full_name())
    if not send_email(message):
        db.rollback()
        raise McAuthRegisterException("Unable to send email about an activated user.")

    db.commit()
