from mediawords.util.config import env_value_or_raise


class NYTLabelsTaggerConfig(object):
    """NYTLabels tagger configuration."""

    @staticmethod
    def version_tag() -> str:
        """NYTLabels version tag, e.g. "nyt_labeller_v1.0.0".

        Will be added under "geocoder_version" tag set."""
        return env_value_or_raise('MC_NYTLABELS_VERSION_TAG')

    @staticmethod
    def tag_set() -> str:
        """NYTLabels version tag, e.g. "nyt_labeller_v1.0.0".

        Will be added under "geocoder_version" tag set."""
        return env_value_or_raise('MC_NYTLABELS_TAG_SET')

