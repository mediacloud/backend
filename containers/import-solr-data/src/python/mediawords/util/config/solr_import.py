from mediawords.util.config import env_value_or_raise


class SolrImportConfig(object):
    """Solr story import script configuration."""

    @staticmethod
    def max_queued_stories() -> int:
        """Number of stories to import in one go."""
        return int(env_value_or_raise('MC_SOLR_IMPORT_MAX_QUEUED_STORIES'))
