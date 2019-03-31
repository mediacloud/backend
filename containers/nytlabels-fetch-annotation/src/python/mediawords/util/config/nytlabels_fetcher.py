from mediawords.util.config import env_value


class NYTLabelsFetcherConfig(object):
    """NYTLabels fetcher configuration."""

    @staticmethod
    def annotator_url() -> str:
        """Annotator URL (text parsing endpoint), e.g. "http://localhost/predict.json"."""
        return env_value('MC_NYTLABELS_ANNOTATOR_URL')
