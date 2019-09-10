from typing import Optional

from mediawords.util.config import env_value


class APCrawlerConfig(object):
    """AP crawler configuration."""

    @staticmethod
    def api_key() -> Optional[str]:
        """"AP API key."""
        return env_value(name='MC_CRAWLER_AP_API_KEY', required=False)
