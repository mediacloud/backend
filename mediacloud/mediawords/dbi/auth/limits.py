from typing import List

from mediawords.db import DatabaseHandler
from mediawords.dbi.auth.roles.list import UserRoles


class McAuthLimitsException(Exception):
    """User limits exception."""
    pass


def default_weekly_requests_limit(db: DatabaseHandler) -> int:
    """Get default weekly request limit."""

    limit = db.query("""
        SELECT column_default AS default_weekly_requests_limit
        FROM information_schema.columns
        WHERE (table_schema, table_name) = ('public', 'auth_user_limits')
          AND column_name = 'weekly_requests_limit'
    """).flat()

    if not limit:
        raise McAuthLimitsException("Unable to fetch default weekly requests limit.")

    return limit[0]


def default_weekly_requested_items_limit(db: DatabaseHandler) -> int:
    """Get default weekly requested items limit."""

    limit = db.query("""
        SELECT column_default AS default_weekly_requested_items_limit
        FROM information_schema.columns
        WHERE (table_schema, table_name) = ('public', 'auth_user_limits')
          AND column_name = 'weekly_requested_items_limit'
    """).flat()

    if not limit:
        raise McAuthLimitsException("Unable to fetch default weekly requested items limit.")

    return limit[0]


def roles_exempt_from_user_limits() -> List[str]:
    """User roles that are not limited by the weekly requests / requested items limits."""
    return [UserRoles.admin(), UserRoles.admin_readonly()]
