from mediawords.util.config import env_value, file_with_env_value


class PodcastTranscribeEpisodeConfig(object):
    """
    Podcast episode fetcher configuration.
    """

    @staticmethod
    def gc_auth_json_file() -> str:
        """Return path to Google Cloud authentication JSON file."""
        return file_with_env_value(name='MC_PODCAST_GC_AUTH_JSON_BASE64', encoded_with_base64=True)

    @staticmethod
    def gc_storage_bucket_name() -> str:
        """Return Google Cloud Storage bucket name."""
        return env_value(name='MC_PODCAST_FETCH_EPISODE_BUCKET_NAME')

    @staticmethod
    def gc_storage_path_prefix() -> str:
        """Return Google Cloud Storage path prefix under which objects will be stored."""
        return env_value(name='MC_PODCAST_FETCH_EPISODE_PATH_PREFIX')
