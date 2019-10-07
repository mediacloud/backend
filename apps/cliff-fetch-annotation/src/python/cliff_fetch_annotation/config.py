class CLIFFFetcherConfig(object):
    """CLIFF fetcher configuration."""

    @staticmethod
    def annotator_url() -> str:
        """Annotator URL (text parsing endpoint), e.g. "http://localhost:8080/."""
        return 'http://cliff-annotator:8080/cliff/parse/text'
