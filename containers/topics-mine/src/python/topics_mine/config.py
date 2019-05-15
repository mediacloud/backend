from mediawords.util.config import env_value


class TopicsMineConfig(object):
    """Topic miner configuration."""

    @staticmethod
    def crimson_hexagon_api_key() -> str:
        """Crimson Hexagon API key."""
        return env_value('MC_CRIMSON_HEXAGON_API_KEY')
