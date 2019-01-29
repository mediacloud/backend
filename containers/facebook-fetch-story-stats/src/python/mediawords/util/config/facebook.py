from mediawords.util.config import env_value


class FacebookConfig(object):
    """Facebook API configuration."""

    @staticmethod
    def app_id() -> str:
        """App ID."""
        return env_value('MC_FACEBOOK_APP_ID')

    @staticmethod
    def app_secret() -> str:
        """App secret."""
        return env_value('MC_FACEBOOK_APP_SECRET')

    @staticmethod
    def timeout() -> int:
        """Timeout."""
        # FIXME probably hardcode somewhere
        return int(env_value('MC_FACEBOOK_TIMEOUT'))

