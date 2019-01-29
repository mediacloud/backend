from mediawords.util.config import env_value


class SolrImportConfig(object):
    """Solr story import script configuration."""

    @staticmethod
    def max_queued_stories() -> int:
        """Number of stories to import in one go."""
        return int(env_value('MC_SOLR_IMPORT_MAX_QUEUED_STORIES'))
