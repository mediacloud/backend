from mediawords.util.config import env_value_or_raise


class CLIFFAnnotatorConfig(object):
    """CLIFF annotator configuration."""

    @staticmethod
    def annotator_url() -> str:
        """Annotator URL (text parsing endpoint), e.g. "http://localhost:8080/."""
        return env_value_or_raise('MC_CLIFF_ANNOTATOR_URL')

