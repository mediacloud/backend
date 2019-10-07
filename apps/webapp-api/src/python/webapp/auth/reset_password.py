from typing import Optional

from furl import furl

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.mail import send_email
from mediawords.util.perl import decode_object_from_bytes_if_needed
from webapp.auth.info import user_info
from webapp.auth.profile import create_password_reset_token
from webapp.mail.messages import AuthResetPasswordMessage

log = create_logger(__name__)


class McAuthResetPasswordException(Exception):
    """Reset password exception."""
    pass


# Kept in a separate subroutine for easier testing.
def _generate_password_reset_token(db: DatabaseHandler, email: str, password_reset_link: str) -> Optional[str]:
    """Generate password reset token; returns None if user was not found."""

    email = decode_object_from_bytes_if_needed(email)
    password_reset_link = decode_object_from_bytes_if_needed(password_reset_link)

    if not email:
        raise McAuthResetPasswordException('Email address is empty.')

    if not password_reset_link:
        raise McAuthResetPasswordException('Activation link is empty.')

    password_reset_token = create_password_reset_token(db=db, email=email)
    if len(password_reset_token) == 0:
        return None

    url = furl(password_reset_link)
    url.args['email'] = email
    url.args['password_reset_token'] = password_reset_token
    return str(url.url)


def send_password_reset_token(db: DatabaseHandler, email: str, password_reset_link: str) -> None:
    """Prepare for password reset by emailing the password reset token."""

    email = decode_object_from_bytes_if_needed(email)
    password_reset_link = decode_object_from_bytes_if_needed(password_reset_link)

    # Check if user exists
    try:
        user = user_info(db=db, email=email)
        full_name = user.full_name()

    except Exception as ex:
        log.warning("Unable to fetch user profile for user '%s': %s" % (email, str(ex),))
        full_name = 'Nonexistent user'

    # If user was not found, send an email to a random address anyway to avoid timing attack
    full_password_reset_link = _generate_password_reset_token(
        db=db,
        email=email,
        password_reset_link=password_reset_link,
    )
    if not full_password_reset_link:
        log.warning("Unable to generate full password reset link for email '%s'" % email)
        email = 'nowhere@mediacloud.org'
        full_password_reset_link = 'password reset link'

    message = AuthResetPasswordMessage(to=email, full_name=full_name, password_reset_url=full_password_reset_link)
    if not send_email(message):
        raise McAuthResetPasswordException('Unable to send password reset email.')
