from mediawords.db import DatabaseHandler
from mediawords.dbi.auth.login import login_with_email_password
from mediawords.dbi.auth.password import validate_new_password, generate_secure_hash, password_reset_token_is_valid
from mediawords.dbi.auth.info import user_info
from mediawords.util.mail import send_email
from mediawords.util.mail_message.templates import AuthPasswordChangedMessage
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McAuthChangePasswordException(Exception):
    """Password change exception."""
    pass


def change_password(db: DatabaseHandler,
                    email: str,
                    new_password: str,
                    new_password_repeat: str,
                    do_not_inform_via_email: bool = False) -> None:
    """Change user's password."""

    email = decode_object_from_bytes_if_needed(email)
    new_password = decode_object_from_bytes_if_needed(new_password)
    new_password_repeat = decode_object_from_bytes_if_needed(new_password_repeat)

    if isinstance(do_not_inform_via_email, bytes):
        do_not_inform_via_email = decode_object_from_bytes_if_needed(do_not_inform_via_email)

    do_not_inform_via_email = bool(int(do_not_inform_via_email))

    # Check if user exists
    try:
        user = user_info(db=db, email=email)
    except Exception:
        raise McAuthChangePasswordException('User with email address "%s" does not exist.' % email)

    password_validation_message = validate_new_password(email=email,
                                                        password=new_password,
                                                        password_repeat=new_password_repeat)
    if password_validation_message:
        raise McAuthChangePasswordException("Unable to change password: %s" % password_validation_message)

    # Hash + validate the password
    try:
        password_new_hash = generate_secure_hash(password=new_password)
    except Exception as ex:
        raise McAuthChangePasswordException("Unable to hash a new password: %s" % str(ex))

    if not password_new_hash:
        raise McAuthChangePasswordException("Generated password hash is empty.")

    # Set the password hash
    db.query("""
        UPDATE auth_users
        SET password_hash = %(password_hash)s,
            active = TRUE
        WHERE email = %(email)s
    """, {
        'email': email,
        'password_hash': password_new_hash,
    })

    if not do_not_inform_via_email:

        message = AuthPasswordChangedMessage(to=email, full_name=user.full_name())
        if not send_email(message):
            raise McAuthChangePasswordException(
                'The password has been changed, but I was unable to send an email notifying you about the change.'
            )


def change_password_with_old_password(db: DatabaseHandler,
                                      email: str,
                                      old_password: str,
                                      new_password: str,
                                      new_password_repeat: str) -> None:
    """Change password by entering old password."""

    email = decode_object_from_bytes_if_needed(email)
    old_password = decode_object_from_bytes_if_needed(old_password)
    new_password = decode_object_from_bytes_if_needed(new_password)
    new_password_repeat = decode_object_from_bytes_if_needed(new_password_repeat)

    # Check if user exists
    try:
        user_info(db=db, email=email)
    except Exception:
        raise McAuthChangePasswordException('User with email address "%s" does not exist.' % email)

    if old_password == new_password:
        raise McAuthChangePasswordException('Old and new passwords are the same.')

    # Validate old password; fetch the hash from the database again because that hash might be outdated (e.g. if the
    # password has been changed already)
    db_password_old = db.query("""
        SELECT auth_users_id,
               email,
               password_hash
        FROM auth_users
        WHERE email = %(email)s
        LIMIT 1
    """, {'email': email}).hash()
    if db_password_old is None or len(db_password_old) == 0:
        raise McAuthChangePasswordException('Unable to find the user in the database.')

    # Validate the password
    try:
        login_with_email_password(db=db, email=email, password=old_password)
    except Exception as ex:
        raise McAuthChangePasswordException("Unable to log in with old password: %s" % str(ex))

    # Execute the change
    try:
        change_password(db=db, email=email, new_password=new_password, new_password_repeat=new_password_repeat)
    except Exception as ex:
        raise McAuthChangePasswordException("Unable to change password: %s" % str(ex))


def change_password_with_reset_token(db: DatabaseHandler,
                                     email: str,
                                     password_reset_token: str,
                                     new_password: str,
                                     new_password_repeat: str) -> None:
    """Change password with a password token sent by email."""

    email = decode_object_from_bytes_if_needed(email)
    password_reset_token = decode_object_from_bytes_if_needed(password_reset_token)
    new_password = decode_object_from_bytes_if_needed(new_password)
    new_password_repeat = decode_object_from_bytes_if_needed(new_password_repeat)

    if not password_reset_token:
        raise McAuthChangePasswordException('Password reset token is empty.')

    # Check if user exists
    try:
        user_info(db=db, email=email)
    except Exception:
        raise McAuthChangePasswordException('User with email address "%s" does not exist.' % email)

    # Validate the token once more (was pre-validated in controller)
    if not password_reset_token_is_valid(db=db, email=email, password_reset_token=password_reset_token):
        raise McAuthChangePasswordException('Password reset token is invalid.')

    # Execute the change
    try:
        change_password(db=db, email=email, new_password=new_password, new_password_repeat=new_password_repeat)
    except Exception as ex:
        raise McAuthChangePasswordException("Unable to change password: %s" % str(ex))

    # Unset the password reset token
    db.query("""
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = %(email)s
    """, {'email': email})
