from mediawords.util.config import env_value


class CLIFFTaggerConfig(object):
    """CLIFF tagger configuration."""

    @staticmethod
    def version_tag() -> str:
        """CLIFF version tag, e.g. "cliff_clavin_v2.4.1"."""
        return env_value('MC_CLIFF_VERSION_TAG')

    @staticmethod
    def geonames_tag_set() -> str:
        """CLIFF geographical names tag set, e.g. "cliff_geonames".

        Tags with names such as "geonames_<countryGeoNameId>" will be added under this tag set."""
        return env_value('MC_CLIFF_GEONAMES_TAG_SET')

    @staticmethod
    def organizations_tag_set() -> str:
        """CLIFF organizations tag set, e.g. "cliff_organizations".

        Tags with names of organizations such as "United Nations" will be added under this tag set."""
        return env_value('MC_CLIFF_ORGANIZATIONS_TAG_SET')

    @staticmethod
    def people_tag_set() -> str:
        """CLIFF people tag set, e.g. "cliff_people".

        Tags with names of people such as "Einstein" will be added under this tag set."""
        return env_value('MC_CLIFF_PEOPLE_TAG_SET')
