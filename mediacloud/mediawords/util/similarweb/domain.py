from typing import Optional
from urllib.parse import urlparse

from mediawords.util.log import create_logger
from mediawords.util.url import fix_common_url_mistakes, is_http_url

log = create_logger(__name__)


def domain_from_url(url: str) -> Optional[str]:
    """Get domain from URL."""
    try:
        url = url.strip()
        url = fix_common_url_mistakes(url)

        assert is_http_url(url), f"URL not HTTP(S) URL: {url}."

        uri = urlparse(url)

        domain_parts = uri.hostname.split('.')

        while len(domain_parts) > 0 and domain_parts[0] == 'www':
            domain_parts.pop(0)

        # Treat ".co.uk" and similar as a single TLD
        second_level_tlds = {'co', 'com', 'gov', 'org', 'net', 'ac', 'ltd', 'me', 'plc', 'priv', 'ac', 'in', 'edu'}
        if domain_parts[-2] not in second_level_tlds and len(domain_parts[-2]) > 3:
            while len(domain_parts) > 3:
                log.warning(
                    f"SimilarWeb API accepts only up to a second-level subdomain, so stripping {domain_parts[0]}"
                )
                domain_parts.pop(0)

        domain = '.'.join(domain_parts)

        return domain

    except Exception as ex:
        log.warning(f"Unable to get domain from URL '{url}': {ex}")
        return None
