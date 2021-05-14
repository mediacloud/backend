import datetime

from mediawords.util.text import random_string


def random_gcs_path_prefix() -> str:
    """
    Generates a random path prefix to store the objects at.

    Makes it easier to debug what gets written to GCS and get rid of said objects afterwards.
    """

    date = datetime.datetime.utcnow().isoformat()
    date = date.replace(':', '_')
    prefix = f'tests-{date}-{random_string(length=32)}'
    return prefix
