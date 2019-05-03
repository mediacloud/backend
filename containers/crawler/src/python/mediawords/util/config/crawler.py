from typing import Optional

from mediawords.util.config import env_value


class CrawlerConfig(object):
    """Crawler configuration."""

    @staticmethod
    def crawler_fetcher_forks() -> int:
    	"""Number of crawler fetcher forks to start."""
    	return int(env_value('MC_CRAWLER_FETCHER_FORKS'))

    @staticmethod
    def univision_client_id() -> Optional[str]:
        """"Univision API client ID."""
        return env_value(name='MC_UNIVISION_CLIENT_ID', required=False, allow_empty_string=True)

    @staticmethod
    def univision_client_secret() -> Optional[str]:
        """Univision API client secret (secret key)."""
        return env_value(name='MC_UNIVISION_CLIENT_SECRET', required=False, allow_empty_string=True)
