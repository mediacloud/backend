from mediawords.db import DatabaseHandler
from mediawords.dbi.auth.password import password_hash_is_valid
from mediawords.dbi.auth.info import user_info
from mediawords.dbi.auth.user import CurrentUser
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

# Post-unsuccessful login delay (in seconds)
__POST_UNSUCCESSFUL_LOGIN_DELAY = 1


class McAuthLoginException(Exception):
    """Login exception."""
    pass


def __user_is_trying_to_login_too_soon(db: DatabaseHandler, email: str) -> bool:
    """Check if user is trying to log in too soon after last unsuccessful attempt to do that."""

    email = decode_object_from_bytes_if_needed(email)

    user = db.query("""
        SELECT auth_users_id,
               email
        FROM auth_users
        WHERE email = %(email)s
          AND last_unsuccessful_login_attempt >= LOCALTIMESTAMP - INTERVAL %(interval)s
        ORDER BY auth_users_id
        LIMIT 1
    """, {
        'email': email,
        'interval': '%d seconds' % __POST_UNSUCCESSFUL_LOGIN_DELAY,
    }).hash()

    if user is not None and 'auth_users_id' in user:
        return True
    else:
        return False


def login_with_email_password(db: DatabaseHandler, email: str, password: str, ip_address: str = None) -> CurrentUser:
    """Log in with username and password; raise on unsuccessful login."""

    email = decode_object_from_bytes_if_needed(email)
    password = decode_object_from_bytes_if_needed(password)

    if not (email and password):
        raise McAuthLoginException("Email and password must be defined.")

    # Try-except block because we don't want to reveal the specific reason why the login has failed
    try:

        user = user_info(db=db, email=email)

        # Check if user has tried to log in unsuccessfully before and now is trying
        # again too fast
        if __user_is_trying_to_login_too_soon(db=db, email=email):
            raise McAuthLoginException(
                "User '%s' is trying to log in too soon after the last unsuccessful attempt." % email
            )

        if not password_hash_is_valid(password_hash=user.password_hash, password=password):
            raise McAuthLoginException("Password for user '%s' is invalid." % email)

    except Exception as ex:
        log.info(
            "Login failed for %(email)s, will delay any successive login attempt for %(delay)d seconds: %(exc)s" % {
                'email': email,
                'delay': __POST_UNSUCCESSFUL_LOGIN_DELAY,
                'exc': str(ex),
            }
        )

        # Set the unsuccessful login timestamp
        # (TIMESTAMP 'now' returns "current transaction's start time", so using LOCALTIMESTAMP instead)
        db.query("""
            UPDATE auth_users
            SET last_unsuccessful_login_attempt = LOCALTIMESTAMP
            WHERE email = %(email)s
        """, {'email': email})

        # It might make sense to time.sleep() here for the duration of $POST_UNSUCCESSFUL_LOGIN_DELAY seconds to prevent
        # legitimate users from trying to log in too fast. However, when being actually brute-forced through multiple
        # HTTP connections, this approach might end up creating a lot of processes that would time.sleep() and take up
        # memory.
        #
        # So, let's return the error page ASAP and hope that a legitimate user won't be able to reenter his / her
        # password before the $POST_UNSUCCESSFUL_LOGIN_DELAY amount of seconds pass.

        # Don't give out a specific reason for the user to not be able to find
        # out which user emails are registered
        raise McAuthLoginException("User '%s' was not found or password is incorrect." % email)

    if not user.active:
        raise McAuthLoginException("User with email '%s' is not active." % email)

    # Reset password reset token (if any)
    db.query("""
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = %(email)s
          AND password_reset_token_hash IS NOT NULL
    """, {'email': email})

    if ip_address:
        if not user.api_key_for_ip_address(ip_address):
            db.create(
                table='auth_user_api_keys',
                insert_hash={
                    'auth_users_id': user.user_id,
                    'ip_address': ip_address,
                })

            # Fetch user again
            user = user_info(db=db, email=email)

            if not user.api_key_for_ip_address(ip_address):
                raise McAuthLoginException("Unable to create per-IP API key for IP %s" % ip_address)

    return user


def login_with_api_key(db: DatabaseHandler, api_key: str, ip_address: str) -> CurrentUser:
    """Fetch user object for the API key. Only active users are fetched."""

    api_key = decode_object_from_bytes_if_needed(api_key)
    ip_address = decode_object_from_bytes_if_needed(ip_address)

    if not api_key:
        raise McAuthLoginException("API key is undefined.")

    if not ip_address:
        # Even if provided API key is the global one, we want the IP address
        raise McAuthLoginException("IP address is undefined.")

    api_key_user = db.query("""
        SELECT auth_users.email
        FROM auth_users
            INNER JOIN auth_user_api_keys
                ON auth_users.auth_users_id = auth_user_api_keys.auth_users_id
        WHERE
            (
                auth_user_api_keys.api_key = %(api_key)s AND
                (
                    auth_user_api_keys.ip_address IS NULL
                    OR
                    auth_user_api_keys.ip_address = %(ip_address)s
                )
            )

        GROUP BY auth_users.auth_users_id,
                 auth_users.email
        ORDER BY auth_users.auth_users_id
        LIMIT 1
    """, {
        'api_key': api_key,
        'ip_address': ip_address,
    }).hash()

    if api_key_user is None or len(api_key_user) == 0:
        raise McAuthLoginException("Unable to find user for API key '%s' and IP address '%s'" % (api_key, ip_address,))

    email = api_key_user['email']

    # Check if user has tried to log in unsuccessfully before and now is trying again too fast
    if __user_is_trying_to_login_too_soon(db=db, email=email):
        raise McAuthLoginException(
            "User '%s' is trying to log in too soon after the last unsuccessful attempt." % email
        )

    user = user_info(db=db, email=email)

    # Reset password reset token (if any)
    db.query("""
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = %(email)s
          AND password_reset_token_hash IS NOT NULL
    """, {'email': email})

    if not user.active:
        raise McAuthLoginException("User '%s' for API key '%s' is not active." % (email, api_key,))

    return user
