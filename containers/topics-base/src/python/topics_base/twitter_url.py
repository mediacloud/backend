import re
from typing import Optional


def parse_status_id_from_url(url: str) -> Optional[str]:
    """Try to parse a twitter status id from a url.  Return the status id or None if not found."""
    m = re.search(r'https?://twitter.com/.*/status/(\d+)(\?.*)?$', url)
    if m:
        return m.group(1)
    else:
        return None


def parse_screen_name_from_user_url(url: str) -> Optional[str]:
    """Try to parse a screen name from a twitter user page url."""
    m = re.search(r'https?://twitter.com/([^/?]+)(\?.*)?$', url)

    if m is None:
        return None

    user = m.group(1)
    if user in ('search', 'login'):
        return None

    return user
