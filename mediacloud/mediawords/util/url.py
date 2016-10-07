import re

from mediawords.util.log import create_logger

l = create_logger(__name__)


def fix_common_url_mistakes(url):
    """Fixes common URL mistakes (mistypes, etc.)."""
    if url is None:
        return None

    # Fix broken URLs that look like this: http://http://www.al-monitor.com/pulse
    url = re.sub(r'(https?://)https?:?//', r"\1", url, flags=re.I)

    # Fix URLs with only one slash after "http" ("http:/www.")
    url = re.sub(r'(https?:/)(www)', r"\1/\2", url, flags=re.I)

    # replace backslashes with forward
    url = re.sub(r'\\', r'/', url)

    # http://newsmachete.com?page=2 -> http://newsmachete.com/?page=2
    url = re.sub(r'(https?://[^/]+)\?', r"\1/?", url)

    return url
