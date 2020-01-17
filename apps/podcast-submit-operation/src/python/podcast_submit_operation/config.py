from mediawords.util.config import file_with_env_value


class PodcastSubmitOperationConfig(object):
    """
    Podcast submit transcription operation configuration.
    """

    @staticmethod
    def gc_auth_json_file() -> str:
        """Return path to Google Cloud authentication JSON file."""
        return file_with_env_value(name='MC_PODCAST_GC_AUTH_JSON_STRING')
