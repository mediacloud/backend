import base64
import hashlib
import os

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

__HASH_SALT_PREFIX = "{SSHA256}"

__HASH_LENGTH = 64  # SHA-256 hash length
__SALT_LENGTH = 64

__MIN_PASSWORD_LENGTH = 8
__MAX_PASSWORD_LENGTH = 120

log = create_logger(__name__)


class McAuthPasswordException(Exception):
    """Password-related exceptions."""
    pass


def password_hash_is_valid(password_hash: str, password: str) -> bool:
    """Validate a password / password token.

    Ported from Crypt::SaltedHash: https://metacpan.org/pod/Crypt::SaltedHash
    """

    password_hash = decode_object_from_bytes_if_needed(password_hash)
    password = decode_object_from_bytes_if_needed(password)

    if not password_hash:
        raise McAuthPasswordException("Password hash is None or empty.")

    if password is None:
        raise McAuthPasswordException("Password is None.")

    # Password can be an empty string but that would be weird so we only spit out a warning
    if not password:
        log.warning("Password is empty.")

    if not password_hash.startswith(__HASH_SALT_PREFIX):
        raise McAuthPasswordException("Password hash does not start with an expected prefix.")

    if len(password_hash) != len(__HASH_SALT_PREFIX) + __HASH_LENGTH + __SALT_LENGTH:
        raise McAuthPasswordException("Password hash is of the incorrect length.")

    try:

        password = password.encode('utf-8', errors='replace')  # to concatenate with 'bytes' salt later

        password_hash = password_hash[len(__HASH_SALT_PREFIX):]

        salted_hash_salt = base64.b64decode(password_hash)

        salt = salted_hash_salt[-1 * __SALT_LENGTH:]
        expected_salted_hash = salted_hash_salt[:len(salted_hash_salt) - __SALT_LENGTH]

        actual_password_salt = password + salt
        sha256 = hashlib.sha256()
        sha256.update(actual_password_salt)
        actual_salted_hash = sha256.digest()

        if expected_salted_hash == actual_salted_hash:
            return True
        else:
            return False

    except Exception as ex:
        log.warning("Failed to validate hash: %s" % str(ex))
        return False


def generate_secure_hash(password: str) -> str:
    """Hash a secure hash (password / password reset token) with a random salt.

    Ported from Crypt::SaltedHash: https://metacpan.org/pod/Crypt::SaltedHash
    """

    password = decode_object_from_bytes_if_needed(password)

    if password is None:
        raise McAuthPasswordException("Password is None.")

    # Password can be an empty string but that would be weird so we only spit out a warning
    if not password:
        log.warning("Password is empty.")

    password = password.encode('utf-8', errors='replace')  # to concatenate with 'bytes' salt later

    # os.urandom() is supposed to be crypto-secure
    salt = os.urandom(__SALT_LENGTH)

    password_salt = password + salt

    sha256 = hashlib.sha256()
    sha256.update(password_salt)
    salted_hash = sha256.digest()

    salted_hash_salt = salted_hash + salt
    base64_salted_hash = base64.b64encode(salted_hash_salt).decode('ascii')

    return __HASH_SALT_PREFIX + base64_salted_hash


def password_reset_token_is_valid(db: DatabaseHandler, email: str, password_reset_token: str) -> bool:
    """Validate password reset token (used for both user activation and password reset)."""
    email = decode_object_from_bytes_if_needed(email)
    password_reset_token = decode_object_from_bytes_if_needed(password_reset_token)

    if not (email and password_reset_token):
        log.error("Email and / or password reset token is empty.")
        return False

    # Fetch readonly information about the user
    password_reset_token_hash = db.query("""
        SELECT auth_users_id,
               email,
               password_reset_token_hash
        FROM auth_users
        WHERE email = %(email)s
        LIMIT 1
    """, {'email': email}).hash()
    if password_reset_token_hash is None or 'auth_users_id' not in password_reset_token_hash:
        log.error("Unable to find user %s in the database." % email)
        return False

    password_reset_token_hash = password_reset_token_hash['password_reset_token_hash']

    if password_hash_is_valid(password_hash=password_reset_token_hash, password=password_reset_token):
        return True
    else:
        return False


def validate_new_password(email: str, password: str, password_repeat: str) -> str:
    """Check if password complies with strength the requirements.

    Returns empty string on valid password, error message on invalid password."""

    email = decode_object_from_bytes_if_needed(email)
    password = decode_object_from_bytes_if_needed(password)
    password_repeat = decode_object_from_bytes_if_needed(password_repeat)

    if not email:
        return 'Email address is empty.'

    if not (password and password_repeat):
        return 'To set the password, please repeat the new password twice.'

    if password != password_repeat:
        return 'Passwords do not match.'

    if len(password) < __MIN_PASSWORD_LENGTH or len(password) > __MAX_PASSWORD_LENGTH:
        return 'Password must be between %d and %d characters length.' % (__MIN_PASSWORD_LENGTH, __MAX_PASSWORD_LENGTH,)

    if password == email:
        return "New password is your email address; don't cheat!"

    return ''
