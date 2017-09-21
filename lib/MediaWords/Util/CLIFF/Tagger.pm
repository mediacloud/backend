package MediaWords::Util::CLIFF::Tagger;

#
# Update story tags using CLIFF annotation
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use HTTP::Status qw(:constants);
use Readonly;

use MediaWords::Util::CLIFF;
use MediaWords::Util::Config;
use MediaWords::Util::JSON;
use MediaWords::Util::Process;

# CLIFF version tag set
Readonly my $CLIFF_VERSION_TAG_SET => 'geocoder_version';

# CLIFF geographical names tag prefix
Readonly my $CLIFF_GEONAMES_TAG_PREFIX => 'geonames_';

# Return array of hashrefs with story tags to add for CLIFF annotation
sub _tags_for_cliff_annotation($)
{
    my $annotation = shift;

    my $config = MediaWords::Util::Config::get_config();

    my $cliff_geonames_tag_set = $config->{ cliff }->{ cliff_geonames_tag_set };
    unless ( $cliff_geonames_tag_set )
    {
        fatal_error( "CLIFF geographical names tag set is unset in configuration." );
    }

    my $results = $annotation->{ results };
    unless ( $results )
    {
        return [];
    }

    my $places = $results->{ places };
    unless ( $places )
    {
        return [];
    }

    my $focus = $places->{ focus };
    unless ( $focus )
    {
        return [];
    }

    my $tags = [];

    my $countries = $focus->{ countries };
    if ( $countries )
    {
        foreach my $country ( @{ $countries } )
        {

            push(
                @{ $tags },
                {
                    tag_sets_name        => $cliff_geonames_tag_set,
                    tag_sets_label       => $cliff_geonames_tag_set,
                    tag_sets_description => 'CLIFF geographical names',

                    # e.g. "geonames_6252001"
                    tags_name => $CLIFF_GEONAMES_TAG_PREFIX . $country->{ id },

                    # e.g. "United States"
                    tags_label => $country->{ name },

                    # e.g. "United States | A | US"
                    tags_description => sprintf(
                        '%s | %s | %s',                #
                        $country->{ name },            #
                        $country->{ featureClass },    #
                        $country->{ countryCode },     #
                    ),
                }
            );
        }
    }

    my $states = $focus->{ states };
    if ( $states )
    {
        foreach my $state ( @{ $states } )
        {

            push(
                @{ $tags },
                {
                    tag_sets_name        => $cliff_geonames_tag_set,
                    tag_sets_label       => $cliff_geonames_tag_set,
                    tag_sets_description => 'CLIFF geographical names',

                    # e.g. "geonames_4273857"
                    tags_name => $CLIFF_GEONAMES_TAG_PREFIX . $state->{ id },

                    # e.g. "Kansas"
                    tags_label => $state->{ name },

                    # e.g. "Kansas | A | KS | US"
                    tags_description => sprintf(
                        '%s | %s | %s | %s',         #
                        $state->{ name },            #
                        $state->{ featureClass },    #
                        $state->{ stateCode },       #
                        $state->{ countryCode },     #
                    ),
                }
            );
        }
    }

    return $tags;
}

# Add CLIFF version, country and story tags for story
sub update_cliff_tags_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( MediaWords::Util::CLIFF::cliff_is_enabled() )
    {
        fatal_error( "CLIFF annotator is not enabled in the configuration." );
    }

    my $config = MediaWords::Util::Config::get_config();

    my $cliff_version_tag = $config->{ cliff }->{ cliff_version_tag };
    unless ( $cliff_version_tag )
    {
        fatal_error( "CLIFF version tag is unset in configuration." );
    }

    my $tags = [];

    push(
        @{ $tags },
        {
            tag_sets_name        => $CLIFF_VERSION_TAG_SET,
            tag_sets_label       => $CLIFF_VERSION_TAG_SET,
            tag_sets_description => 'CLIFF version the story was tagged with',

            tags_name        => $cliff_version_tag,
            tags_label       => $cliff_version_tag,
            tags_description => "Story was tagged with '$cliff_version_tag'",
        }
    );

    my $annotation = MediaWords::Util::CLIFF::fetch_annotation_for_story( $db, $stories_id );
    unless ( $annotation )
    {
        die "Unable to fetch CLIFF annotation for story $stories_id";
    }

    unless ( lc( $annotation->{ status } ) eq 'ok' )
    {
        die "CLIFF annotation was not successful for story $stories_id; annotation: " . Dumper( $annotation );
    }

    my $cliff_tags = _tags_for_cliff_annotation( $annotation );
    push( @{ $tags }, @{ $cliff_tags } );

    DEBUG "CLIFF tags for story $stories_id: " . Dumper( $tags );

    $db->begin;

    foreach my $tag ( @{ $tags } )
    {
        # Delete old tags the story might have under a given tag set
        $db->query(
            <<SQL,
            DELETE FROM stories_tags_map
                USING tags, tag_sets
            WHERE stories_tags_map.tags_id = tags.tags_id
              AND tags.tag_sets_id = tag_sets.tag_sets_id
              AND stories_tags_map.stories_id = ?
              AND tag_sets.name = ?
SQL
            $stories_id, $tag->{ tag_sets_name }
        );
    }

    foreach my $tag ( @{ $tags } )
    {
        # Create tag set
        my $tag_set = $db->find_or_create(
            'tag_sets',
            {
                name        => $tag->{ tag_sets_name },
                label       => $tag->{ tag_sets_label },
                description => $tag->{ tag_sets_description },
            }
        );
        my $tag_sets_id = $tag_set->{ tag_sets_id };

        # Create tag
        my $tag = $db->find_or_create(
            'tags',
            {
                tag_sets_id => $tag_sets_id,
                tag         => $tag->{ tags_name },
                label       => $tag->{ tags_label },
                description => $tag->{ tags_description },
            }
        );
        my $tags_id = $tag->{ tags_id };

        # Assign story to tag
        $db->create(
            'stories_tags_map',
            {
                tags_id    => $tags_id,
                stories_id => $stories_id,
            }
        );
    }

    $db->commit;
}

1;
