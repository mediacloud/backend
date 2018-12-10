from mediawords.util.config import env_value_or_raise


class SimilarWebConfig(object):
    """SimilarWeb configuration."""

    @staticmethod
    def api_key() -> str:
        """API key.

        Costs money, see at https://developer.similarweb.com/."""
        return env_value_or_raise('MC_SIMILARWEB_API_KEY')

