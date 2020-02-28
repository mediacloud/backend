import datetime

from podcast_fetch_episode.config import PodcastFetchEpisodeConfig


class RandomPathPrefixConfig(PodcastFetchEpisodeConfig):
    """Configuration which stores GCS objects under a timestamped prefix."""
    _RANDOM_PREFIX = None

    @staticmethod
    def gc_storage_path_prefix() -> str:
        if not RandomPathPrefixConfig._RANDOM_PREFIX:
            date = datetime.datetime.utcnow().isoformat()
            date = date.replace(':', '_')
            RandomPathPrefixConfig._RANDOM_PREFIX = f'tests-{date}'
        return RandomPathPrefixConfig._RANDOM_PREFIX
