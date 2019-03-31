from typing import Union, List

from mediawords.annotator.cliff_store import CLIFFAnnotatorStore
from mediawords.annotator.tagger import JSONAnnotationTagger, McJSONAnnotationTaggerException
from mediawords.util.config.cliff_tagger import CLIFFTaggerConfig
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class CLIFFTagger(JSONAnnotationTagger):
    """CLIFF tagger."""

    # CLIFF version tag set
    __CLIFF_VERSION_TAG_SET = 'geocoder_version'

    # CLIFF geographical names tag prefix
    __CLIFF_GEONAMES_TAG_PREFIX = 'geonames_'

    def __init__(self):
        store = CLIFFAnnotatorStore()
        super().__init__(annotation_store=store)

    def _tags_for_annotation(self, annotation: Union[dict, list]) -> List[JSONAnnotationTagger.Tag]:

        annotation = decode_object_from_bytes_if_needed(annotation)

        cliff_version_tag = CLIFFTaggerConfig.version_tag()
        if cliff_version_tag is None:
            raise McJSONAnnotationTaggerException("CLIFF version tag is unset in configuration.")

        cliff_geonames_tag_set = CLIFFTaggerConfig.geonames_tag_set()
        if cliff_geonames_tag_set is None:
            raise McJSONAnnotationTaggerException("CLIFF geographical names tag set is unset in configuration.")

        cliff_organizations_tag_set = CLIFFTaggerConfig.organizations_tag_set()
        if cliff_organizations_tag_set is None:
            raise McJSONAnnotationTaggerException("CLIFF organizations tag set is unset in configuration.")

        cliff_people_tag_set = CLIFFTaggerConfig.people_tag_set()
        if cliff_people_tag_set is None:
            raise McJSONAnnotationTaggerException("CLIFF people tag set is unset in configuration.")

        tags = list()

        tags.append(CLIFFTagger.Tag(tag_sets_name=self.__CLIFF_VERSION_TAG_SET,
                                    tag_sets_label=self.__CLIFF_VERSION_TAG_SET,
                                    tag_sets_description='CLIFF version the story was tagged with',
                                    tags_name=cliff_version_tag,
                                    tags_label=cliff_version_tag,
                                    tags_description="Story was tagged with '%s'" % cliff_version_tag))

        results = annotation.get('results', None)
        if results is None or len(results) == 0:
            return tags

        organizations = results.get('organizations', None)
        if organizations is not None:
            for organization in organizations:
                tags.append(CLIFFTagger.Tag(tag_sets_name=cliff_organizations_tag_set,
                                            tag_sets_label=cliff_organizations_tag_set,
                                            tag_sets_description='CLIFF organizations',

                                            # e.g. "United Nations"
                                            tags_name=organization['name'],
                                            tags_label=organization['name'],
                                            tags_description=organization['name']))

        people = results.get('people', None)
        if people is not None:
            for person in people:
                tags.append(CLIFFTagger.Tag(tag_sets_name=cliff_people_tag_set,
                                            tag_sets_label=cliff_people_tag_set,
                                            tag_sets_description='CLIFF people',

                                            # e.g. "Einstein"
                                            tags_name=person['name'],
                                            tags_label=person['name'],
                                            tags_description=person['name']))

        places = results.get('places', None)
        if places is not None:
            focus = places.get('focus', None)
            if focus is not None:

                countries = focus.get('countries', None)
                if countries is not None:

                    for country in countries:
                        tags.append(CLIFFTagger.Tag(tag_sets_name=cliff_geonames_tag_set,
                                                    tag_sets_label=cliff_geonames_tag_set,
                                                    tag_sets_description='CLIFF geographical names',

                                                    # e.g. "geonames_6252001"
                                                    tags_name=self.__CLIFF_GEONAMES_TAG_PREFIX + str(country['id']),

                                                    # e.g. "United States"
                                                    tags_label=country['name'],

                                                    # e.g. "United States | A | US"
                                                    tags_description='%(name)s | %(feature)s | %(country)s' % {
                                                        'name': country['name'],
                                                        'feature': country['featureClass'],
                                                        'country': country['countryCode'],
                                                    }))

                states = focus.get('states', None)
                if states is not None:

                    for state in states:
                        tags.append(CLIFFTagger.Tag(tag_sets_name=cliff_geonames_tag_set,
                                                    tag_sets_label=cliff_geonames_tag_set,
                                                    tag_sets_description='CLIFF geographical names',

                                                    # e.g. "geonames_4273857"
                                                    tags_name=self.__CLIFF_GEONAMES_TAG_PREFIX + str(state['id']),

                                                    # e.g. "Kansas"
                                                    tags_label=state['name'],

                                                    # e.g. "Kansas | A | KS | US"
                                                    tags_description=('%(name)s | %(feature)s | '
                                                                      '%(state)s | %(country)s') % {
                                                                         'name': state['name'],
                                                                         'feature': state['featureClass'],
                                                                         'state': state['stateCode'],
                                                                         'country': state['countryCode'],
                                                                     }))

                cities = focus.get('cities', None)
                if cities is not None:

                    for city in cities:
                        tags.append(CLIFFTagger.Tag(tag_sets_name=cliff_geonames_tag_set,
                                                    tag_sets_label=cliff_geonames_tag_set,
                                                    tag_sets_description='CLIFF geographical names',

                                                    # e.g. "geonames_4273857"
                                                    tags_name=self.__CLIFF_GEONAMES_TAG_PREFIX + str(city['id']),

                                                    # e.g. "Kansas"
                                                    tags_label=city['name'],

                                                    # e.g. "Kansas | A | KS | US"
                                                    tags_description=('%(name)s | %(feature)s | '
                                                                      '%(state)s | %(country)s') % {
                                                                         'name': city['name'],
                                                                         'feature': city['featureClass'],
                                                                         'state': city['stateCode'],
                                                                         'country': city['countryCode'],
                                                                     }))

        return tags
