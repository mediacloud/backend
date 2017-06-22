import re
from urllib.parse import urljoin
from typing import Optional

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import URL_REGEX

l = create_logger(__name__)


def link_canonical_url_from_html(html: str, base_url: str = None) -> Optional[str]:
    """From the provided HTML, determine the <link rel="canonical" /> URL (if any)."""
    html = decode_object_from_bytes_if_needed(html)
    base_url = decode_object_from_bytes_if_needed(base_url)

    link_elements = re.findall(r'(<\s*?link.+?>)', html, re.I)
    for link_element in link_elements:
        if re.search(r'rel\s*?=\s*?["\']\s*?canonical\s*?["\']', link_element, re.I):
            url = re.search(r'href\s*?=\s*?["\'](.+?)["\']', link_element, re.I)
            if url:
                url = url.group(1)
                if not re.search(URL_REGEX, url):
                    # Maybe it's absolute path?
                    if base_url is not None:
                        return urljoin(base=base_url, url=url)
                    else:
                        l.debug("HTML <link rel=\"canonical\"/> found, but the new URL '%s' doesn't seem to be valid."
                                % url)
                else:
                    # Looks like URL, so return it
                    return url
    return None
