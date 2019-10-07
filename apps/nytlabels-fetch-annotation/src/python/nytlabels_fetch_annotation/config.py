class NYTLabelsFetcherConfig(object):
    """NYTLabels fetcher configuration."""

    @staticmethod
    def annotator_url() -> str:
        """Annotator URL (text parsing endpoint), e.g. "http://localhost/predict.json"."""
        return 'http://nytlabels-annotator:8080/predict.json'
