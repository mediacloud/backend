from mediawords.util.config import env_value


class CLIFFAnnotatorConfig(object):
    """CLIFF annotator configuration."""

    @staticmethod
    def annotator_url() -> str:
        """Annotator URL (text parsing endpoint), e.g. "http://localhost:8080/."""
        return env_value('MC_CLIFF_ANNOTATOR_URL')

