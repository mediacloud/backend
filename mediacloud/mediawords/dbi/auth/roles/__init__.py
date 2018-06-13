"""
Authentication role helpers.
"""

from typing import List

from mediawords.db import DatabaseHandler
from mediawords.dbi.auth.roles.list import UserRoles
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McRolesException(Exception):
    """Roles exception."""
    pass


class McRoleIDForRoleException(Exception):
    """role_id_for_role() exception."""
    pass


def all_user_roles(db: DatabaseHandler) -> List[dict]:
    """Fetch a list of available user roles."""
    # MC_REWRITE_TO_PYTHON: could return a set after Python rewrite
    roles = db.query("""
        SELECT auth_roles_id,
               role,
               description
        FROM auth_roles
        ORDER BY auth_roles_id
    """).hashes()
    if roles is None:
        roles = []

    # MC_REWRITE_TO_PYTHON: if only a single item is to be returned, Perl doesn't bother to make it into a list
    if isinstance(roles, dict):
        roles = [roles]

    return roles


def role_id_for_role(db: DatabaseHandler, role: str) -> int:
    """Fetch a user role's ID for a role; raise if no such role was found."""
    role = decode_object_from_bytes_if_needed(role)

    if not role:
        raise McRoleIDForRoleException("Role is empty.")

    auth_roles_id = db.query("""
        SELECT auth_roles_id
        FROM auth_roles
        WHERE role = %(role)s
        LIMIT 1
    """, {'role': role}).flat()

    if (not auth_roles_id) or (not len(auth_roles_id)):
        raise McRoleIDForRoleException("Role '%s' was not found." % role)

    return int(auth_roles_id[0])


def default_role_ids(db: DatabaseHandler) -> List[int]:
    """List of role IDs to apply to new users."""
    default_roles = db.query("""
        SELECT auth_roles_id
        FROM auth_roles
        WHERE role = %(role)s
    """, {'role': UserRoles.search()}).flat()
    if (not default_roles) or (not len(default_roles)):
        raise McRoleIDForRoleException('Unable to find default role IDs.')
    if default_roles is None:
        default_roles = []

    # MC_REWRITE_TO_PYTHON: if only a single item is to be returned, Perl doesn't bother to make it into a list
    if isinstance(default_roles, int):
        default_roles = [default_roles]

    return default_roles
