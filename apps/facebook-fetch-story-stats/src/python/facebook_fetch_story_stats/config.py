from mediawords.util.config import env_value


class FacebookConfig(object):
    """Facebook API configuration."""

    @staticmethod
    def is_enabled() -> bool:
        """Return True if Facebook processing is enabled."""
        if FacebookConfig.app_id() and FacebookConfig.app_secret():
            return True
        else:
            return False

    @staticmethod
    def api_endpoint() -> str:
        """API endpoint to use, together with version."""
        return "https://graph.facebook.com/v5.0/"

    @staticmethod
    def app_id() -> str:
        """App ID."""
        return env_value('MC_FACEBOOK_APP_ID')

    @staticmethod
    def app_secret() -> str:
        """App secret."""
        return env_value('MC_FACEBOOK_APP_SECRET')

    @staticmethod
    def seconds_to_wait_between_retries() -> int:
        """How many seconds to wait between retries on temporary errors."""
        return 60
