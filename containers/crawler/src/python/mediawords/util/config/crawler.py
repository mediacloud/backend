from mediawords.util.config import env_value_or_raise


class CrawlerConfig(object):
    """Crawler configuration."""

    @staticmethod
    def univision_client_id() -> str:
        """"Univision API client ID."""
        return env_value_or_raise('MC_UNIVISION_CLIENT_ID')

    @staticmethod
    def univision_client_secret() -> str:
        """Univision API client secret (secret key)."""
        return env_value_or_raise('MC_UNIVISION_CLIENT_SECRET')

