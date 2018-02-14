"""Various utility functions for handling html."""

from bs4 import BeautifulSoup
import re
from urllib.parse import urljoin
from typing import Optional

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import is_http_url

log = create_logger(__name__)


def link_canonical_url_from_html(html: str, base_url: Optional[str]= None) -> Optional[str]:
    """From the provided HTML, determine the <link rel="canonical" /> URL (if any)."""
    html = str(decode_object_from_bytes_if_needed(html))

    base_url_decode = decode_object_from_bytes_if_needed(base_url)
    base_url = None if base_url_decode is None else str(base_url_decode)

    link_elements = re.findall(r'(<\s*?link.+?>)', html, re.I)
    for link_element in link_elements:
        if re.search(r'rel\s*?=\s*?["\']\s*?canonical\s*?["\']', link_element, re.I):
            match = re.search(r'href\s*?=\s*?["\'](.+?)["\']', link_element, re.I)
            if match:
                url = str(match.group(1))
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


def meta_refresh_url_from_html(html: str, base_url: Optional[str] = None) -> Optional[str]:
    """From the provided HTML, determine the <meta http-equiv="refresh" /> URL (if any)."""
    def __get_meta_refresh_url_from_tag(inner_tag: str, inner_base_url: Optional[str]=None) -> Optional[str]:
        """Given a <meta ...> tag, return the url from the content="url=XXX" attribute.

        return undef if no such url isfound.
        """
        if not re.search(r'http-equiv\s*?=\s*?["\']\s*?refresh\s*?["\']', inner_tag, re.I):
            return None

        # content="url='http://foo.bar'"
        inner_url = None

        match = re.search(r'content\s*?=\s*?"\d*?\s*?;?\s*?URL\s*?=\s*?\'(.+?)\'', inner_tag, re.I)
        if match:
            inner_url = str(match.group(1))
        else:
            # content="url='http://foo.bar'"
            match = re.search(r'content\s*?=\s*?\'\d*?\s*?;?\s*?URL\s*?=\s*?"(.+?)"', inner_tag, re.I)
            if match:
                inner_url = str(match.group(1))
            else:
                # Fallback
                match = re.search(r'content\s*?=\s*?["\']\d*?\s*?;?\s*?URL\s*?=\s*?(.+?)["\']', inner_tag, re.I)
                if match:
                    inner_url = str(match.group(1))

        if is_http_url(str(inner_url)):
            return inner_url

        if inner_base_url is not None:
            return urljoin(base=str(inner_base_url), url=str(inner_url))

        return None

    html = str(decode_object_from_bytes_if_needed(html))
    base_url_decode = decode_object_from_bytes_if_needed(base_url)
    base_url = None if base_url_decode is None else str(base_url_decode)

    if not is_http_url(str(base_url)):
        log.info("Base URL is not HTTP(s): %s" % base_url)

    tags = re.findall(r'(<\s*meta[^>]+>)', html, re.I)
    for tag in tags:
        url = __get_meta_refresh_url_from_tag(tag, base_url)
        if url is not None:
            return url

    return None


def _sententize_block_level_tags(s: str) -> str:
    """Add a double newline after each block level tag and a newline before the end of each block level tag.

    Arguments:
    s - html string

    Returns:
    string with tags replaced.

    """
    _BLOCK_LEVEL_ELEMENT_TAGS = \
        ('title h1 h2 h3 h4 h5 h6 p div dl dt dd ol ul li dir menu address'
         ' blockquote center div hr ins noscript pre').split()
    _TAG_LIST = '|'.join(_BLOCK_LEVEL_ELEMENT_TAGS)
    _BLOCK_LEVEL_START_TAG_RE = r'(<(' + _TAG_LIST + ')(>|\s))'
    _BLOCK_LEVEL_END_TAG_RE = r'(</(' + _TAG_LIST + ')>)'

    s = re.sub(_BLOCK_LEVEL_START_TAG_RE, "\n\n\\1", s, flags=re.S | re.I)
    s = re.sub(_BLOCK_LEVEL_END_TAG_RE, ".\\1\n\n", s, flags=re.S | re.I)

    # get rid of repeat periods
    s = re.sub(r'\.(\s*\.)+', '.', s, flags=re.S)
    s = re.sub(r'^(\s*\.\s)+', '', s, flags=re.S)

    return s


def html_strip(s: str, include_title: bool=False) -> str:
    """Strip the html tags, html comments, any any text within TITLE, SCRIPT, APPLET, OBJECT, and STYLE tags.

    Derived from code by powerman from: http://www.perlmonks.org/?node_id=161281.

    Arguments:
    s - html to strip
    include_title - if true, the title text in the returned text
    """
    s = str(decode_object_from_bytes_if_needed(s))

    # help the sentence parse understand headers as individual sentences
    s = _sententize_block_level_tags(s)

    # Remove soft hyphen (&shy or 0xAD) character from text
    # (some news websites hyphenate their stories using this character so that the browser can lay it out more nicely)
    s = re.sub('\xAD', '', s, flags=re.S)

    soup = BeautifulSoup(s, 'lxml')

    remove_tags = 'script applet object style'.split()
    if not include_title:
        remove_tags.append('title')

    for tag in soup(remove_tags):
        tag.decompose()

    text = soup.get_text(' ', strip=True)

    return text.strip()


def html_title(html: str, fallback: str, trim_to_length: int=0) -> Optional[str]:
    """Parse the content for tags that might indicate the story's title.

    Arguments:
    html - html to parse for title
    fallback - a default title to return if none is found in the html
    trim_to_length - if specified, trim the title to this length

    Returns:
    the title

    """
    html = str(decode_object_from_bytes_if_needed(html))
    fallback_decode = decode_object_from_bytes_if_needed(fallback)
    fallback = '' if fallback_decode is None else str(fallback_decode)
    title = None

    match = re.search("<meta property=\"og:title\" content=\"([^\"]+)\"", html, flags=re.S | re.I)
    title = match.group(1) if match else None

    if title is None:
        match = re.search("<meta property=\"og:title\" content=\'([^\']+)\'", html, flags=re.S | re.I)
        title = match.group(1) if match else None

    if title is None:
        match = re.search("<title>(.*?)</title>", html, flags=re.S | re.I)
        title = match.group(1) if match else None

    if title:
        title = html_strip(title)
        title = title.strip()
        title = re.sub(r'\s+', ' ', title)

        # Moved from _get_medium_title_from_response()
        title = re.sub(r'^\W*home\W*', '', title, flags=re.I)

    if title is None or title == '':
        title = fallback

    if trim_to_length > 0:
        title = title[0:trim_to_length]

    return title
