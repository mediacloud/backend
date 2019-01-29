from mediawords.util.config import env_value


class SimilarWebConfig(object):
    """SimilarWeb configuration."""

    @staticmethod
    def api_key() -> str:
        """API key.

        Costs money, see at https://developer.similarweb.com/."""
        return env_value('MC_SIMILARWEB_API_KEY')

