from mediawords.util.config import env_value_or_raise


class NYTLabelsAnnotatorConfig(object):
    """NYTLabels annotator configuration."""

    @staticmethod
    def annotator_url() -> str:
        """Annotator URL (text parsing endpoint), e.g. "http://localhost/predict.json"."""
        return env_value_or_raise('MC_NYTLABELS_ANNOTATOR_URL')

