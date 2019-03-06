from typing import Optional

from mediawords.util.log import create_logger
from mediawords.util.url import fix_common_url_mistakes, is_http_url, get_url_distinctive_domain

log = create_logger(__name__)


def domain_from_url(url: str) -> Optional[str]:
    """Get domain from URL."""
    try:
        url = url.strip()
        url = fix_common_url_mistakes(url)

        assert is_http_url(url), f"URL not HTTP(S) URL: {url}."

        domain = get_url_distinctive_domain(url)
        if domain.lower() == url.lower():
            log.warning(f"get_url_distinctive_domain() returned an unmodified URL: {url}")
            return None

        if not 1 <= domain.count('.') <= 2:
            log.warning(f"Domain for URL {url} should be a top-level domain or a second-level subdomain: {domain}")
            return None

        return domain

    except Exception as ex:
        log.warning(f"Unable to get domain from URL '{url}': {ex}")
        return None
