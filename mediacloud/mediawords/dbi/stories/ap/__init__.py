from mediawords.db import DatabaseHandler


def get_ap_medium_name() -> str:
    return 'Associated Press - Full Feed'


def is_syndicated(db: DatabaseHandler, story: dict) -> bool:
    """Return True if the stories is syndicated by the AP, False otherwise.

    Uses the decision tree at the top of the module.
    """
    return False  # FIXME not implemented
