from typing import List


class UserRoles(object):
    """Authentication roles (keep in sync with "auth_roles" table)."""

    # MC_REWRITE_TO_PYTHON make it into an enum? Currently a list of stings to make the rewrite easier

    @staticmethod
    def admin() -> str:
        """Do everything, including editing users."""
        return 'admin'

    @staticmethod
    def admin_readonly() -> str:
        """Read-only access to admin interface."""
        return 'admin-readonly'

    @staticmethod
    def media_edit() -> str:
        """Add / edit media; includes feeds."""
        return 'media-edit'

    @staticmethod
    def stories_edit() -> str:
        """Add / edit stories."""
        return 'stories-edit'

    @staticmethod
    def tm() -> str:
        """Topic mapper; includes media and story editing."""
        return 'tm'

    @staticmethod
    def tm_readonly() -> str:
        """Topic mapper; excludes media and story editing."""
        return 'tm-readonly'


def topic_mc_queue_roles() -> List[str]:
    """Roles that are allows to queue a topic into the 'mc' queue instead of the 'public' queue."""
    return [
        UserRoles.admin(),
        UserRoles.admin_readonly(),
        UserRoles.media_edit(),
        UserRoles.stories_edit(),
        UserRoles.tm()
    ]
