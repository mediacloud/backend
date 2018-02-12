import re
from urllib.parse import urljoin
from typing import Optional

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import is_http_url

log = create_logger(__name__)


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
                if not is_http_url(url):
                    # Maybe it's absolute path?
                    if base_url is not None:
                        return urljoin(base=base_url, url=url)
                    else:
                        log.debug(
                            "HTML <link rel='canonical'/> found, but the new URL '%s' doesn't seem to be valid." % url
                        )
                else:
                    # Looks like URL, so return it
                    return url
    return None


def meta_refresh_url_from_html(html: str, base_url: str = None) -> Optional[str]:
    """From the provided HTML, determine the <meta http-equiv="refresh" /> URL (if any)."""

    def __get_meta_refresh_url_from_tag(inner_tag: str, inner_base_url=None) -> Optional[str]:
        """Given a <meta ...> tag, return the url from the content="url=XXX" attribute.  return undef if no such url is
        found."""
        if not re.search(r'http-equiv\s*?=\s*?["\']\s*?refresh\s*?["\']', inner_tag, re.I):
            return None

        # content="url='http://foo.bar'"
        inner_url = None

        match = re.search(r'content\s*?=\s*?"\d*?\s*?;?\s*?URL\s*?=\s*?\'(.+?)\'', inner_tag, re.I)
        if match:
            inner_url = match.group(1)
        else:
            # content="url='http://foo.bar'"
            match = re.search(r'content\s*?=\s*?\'\d*?\s*?;?\s*?URL\s*?=\s*?"(.+?)"', inner_tag, re.I)
            if match:
                inner_url = match.group(1)
            else:
                # Fallback
                match = re.search(r'content\s*?=\s*?["\']\d*?\s*?;?\s*?URL\s*?=\s*?(.+?)["\']', inner_tag, re.I)
                if match:
                    inner_url = match.group(1)

        if is_http_url(inner_url):
            return inner_url

        if inner_base_url is not None:
            return urljoin(base=inner_base_url, url=inner_url)

        return None

    html = decode_object_from_bytes_if_needed(html)
    base_url = decode_object_from_bytes_if_needed(base_url)

    if not is_http_url(base_url):
        log.error("Base URL is not HTTP(s): %s" % base_url)

    tags = re.findall(r'(<\s*meta[^>]+>)', html, re.I)
    for tag in tags:
        url = __get_meta_refresh_url_from_tag(tag, base_url)
        if url is not None:
            return url

    return None
