from mediawords.db import DatabaseHandler
from mediawords.dbi.auth.user import CurrentUser, Role, APIKey
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McAuthInfoException(Exception):
    """Profile information exception."""
    pass


def user_info(db: DatabaseHandler, email: str) -> CurrentUser:
    """Fetch user information (email, full name, notes, API keys, password hash).

    Raises on error if user is not found.
    """

    email = decode_object_from_bytes_if_needed(email)

    if not email:
        raise McAuthInfoException("User email is not defined.")

    # Fetch read-only information about the user
    user = db.query("""
        SELECT auth_users.auth_users_id,
               auth_users.email,
               auth_users.full_name,
               auth_users.notes,
               EXTRACT(EPOCH FROM NOW())::BIGINT AS created_timestamp,
               auth_users.active,
               auth_users.password_hash,
               auth_user_api_keys.api_key,
               auth_user_api_keys.ip_address,
               weekly_requests_sum,
               weekly_requested_items_sum,
               auth_user_limits.weekly_requests_limit,
               auth_user_limits.weekly_requested_items_limit,
               auth_roles.auth_roles_id,
               auth_roles.role

        FROM auth_users
            INNER JOIN auth_user_api_keys
                ON auth_users.auth_users_id = auth_user_api_keys.auth_users_id
            INNER JOIN auth_user_limits
                ON auth_users.auth_users_id = auth_user_limits.auth_users_id
            LEFT JOIN auth_users_roles_map
                ON auth_users.auth_users_id = auth_users_roles_map.auth_users_id
            LEFT JOIN auth_roles
                ON auth_users_roles_map.auth_roles_id = auth_roles.auth_roles_id,
            auth_user_limits_weekly_usage( %(email)s )

        WHERE auth_users.email = %(email)s
    """, {'email': email}).hashes()
    if user is None or len(user) == 0:
        raise McAuthInfoException("User with email '%s' was not found." % email)

    unique_api_keys = dict()
    unique_roles = dict()

    for row in user:
        # Should have at least one API key
        unique_api_keys[row['api_key']] = row['ip_address']

        # Might have some roles
        if row['auth_roles_id'] is not None:
            unique_roles[row['auth_roles_id']] = row['role']

    api_keys = []
    for api_key in sorted(unique_api_keys.keys()):
        api_keys.append(APIKey(api_key=api_key, ip_address=unique_api_keys[api_key]))

    roles = []
    for role_id in sorted(unique_roles.keys()):
        roles.append(Role(role_id=role_id, role_name=unique_roles[role_id]))

    first_row = user[0]

    return CurrentUser(
        user_id=first_row['auth_users_id'],
        email=email,
        full_name=first_row['full_name'],
        notes=first_row['notes'],
        created_timestamp=first_row['created_timestamp'],
        active=bool(int(first_row['active'])),
        password_hash=first_row['password_hash'],
        roles=roles,
        api_keys=api_keys,
        weekly_requests_limit=first_row['weekly_requests_limit'],
        weekly_requested_items_limit=first_row['weekly_requested_items_limit'],
        weekly_requests_sum=first_row['weekly_requests_sum'],
        weekly_requested_items_sum=first_row['weekly_requested_items_sum'],
    )
