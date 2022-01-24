from mediawords.db import DatabaseHandler
from mediawords.util.perl import decode_object_from_bytes_if_needed
from webapp.auth.user import CurrentUser, Role, APIKey, Resources


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
        SELECT
            auth_users.auth_users_id,
            auth_users.email,
            auth_users.full_name,
            auth_users.notes,
            EXTRACT(EPOCH FROM NOW())::BIGINT AS created_timestamp,
            auth_users.active,
            auth_users.has_consented,
            auth_users.password_hash,
            auth_user_api_keys.api_key,
            auth_user_api_keys.ip_address,
            auth_user_limits.weekly_requests_limit,
            auth_user_limits.weekly_requested_items_limit,
            auth_user_limits.max_topic_stories,
            auth_roles.auth_roles_id,
            auth_roles.role,
            COALESCE(
                SUM(auth_user_request_daily_counts.requests_count),
                0
            ) AS weekly_requests_sum,
            COALESCE(
                SUM(auth_user_request_daily_counts.requested_items_count),
                0
            ) AS weekly_requested_items_sum

        FROM auth_users
            INNER JOIN auth_user_api_keys ON
                auth_users.auth_users_id = auth_user_api_keys.auth_users_id
            INNER JOIN auth_user_limits ON
                auth_users.auth_users_id = auth_user_limits.auth_users_id
            LEFT JOIN auth_users_roles_map ON
                auth_users.auth_users_id = auth_users_roles_map.auth_users_id
            LEFT JOIN auth_roles ON
                auth_users_roles_map.auth_roles_id = auth_roles.auth_roles_id
            LEFT JOIN auth_user_request_daily_counts ON
                auth_users.email = auth_user_request_daily_counts.email AND
                auth_user_request_daily_counts.day > DATE_TRUNC('day', NOW())::date - INTERVAL '1 week'

        WHERE auth_users.email = %(email)s
        GROUP BY
            auth_users.auth_users_id,
            auth_user_api_keys.api_key,
            auth_user_api_keys.ip_address,
            auth_user_limits.weekly_requests_limit,
            auth_user_limits.weekly_requested_items_limit,
            auth_user_limits.max_topic_stories,
            auth_roles.auth_roles_id,
            auth_roles.role
    """, {
        'email': email,
    }).hashes()
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
        has_consented=bool(int(first_row['has_consented'])),
        password_hash=first_row['password_hash'],
        roles=roles,
        api_keys=api_keys,
        resource_limits=Resources(
            weekly_requests=first_row['weekly_requests_limit'],
            weekly_requested_items=first_row['weekly_requested_items_limit'],
            max_topic_stories=first_row['max_topic_stories'],
        ),
        used_resources=Resources(
            weekly_requests=first_row['weekly_requests_sum'],
            weekly_requested_items=first_row['weekly_requested_items_sum'],
            max_topic_stories=0,
        ),
    )
