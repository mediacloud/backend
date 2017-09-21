package MediaWords::Util::NYTLabels::Tagger;

#
# Update story tags using NYTLabels annotation
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use HTTP::Status qw(:constants);
use Readonly;

use MediaWords::Util::Config;
use MediaWords::Util::JSON;
use MediaWords::Util::NYTLabels;
use MediaWords::Util::Process;

# NYTLabels version tag set
Readonly my $NYTLABELS_VERSION_TAG_SET => 'nyt_labels_version';

# Story will be tagged with labels for which the score is above this threshold
Readonly my $NYTLABELS_SCORE_THRESHOLD => 0.50;

# Return array of hashrefs with story tags to add for NYTLabels annotation
sub _tags_for_nytlabels_annotation($)
{
    my $annotation = shift;

    my $config = MediaWords::Util::Config::get_config();

    my $nytlabels_labels_tag_set = $config->{ nytlabels }->{ nytlabels_labels_tag_set };
    unless ( $nytlabels_labels_tag_set )
    {
        fatal_error( "NYTLabels labels tag set is unset in configuration." );
    }

    my $descriptors600 = $annotation->{ descriptors600 };
    unless ( $descriptors600 )
    {
        return [];
    }

    my $tags = [];

    foreach my $descriptor ( @{ $descriptors600 } )
    {
        my $label = $descriptor->{ label };
        my $score = $descriptor->{ score } + 0.0;

        if ( $score > $NYTLABELS_SCORE_THRESHOLD + 0.0 )
        {
            push(
                @{ $tags },
                {
                    tag_sets_name        => $nytlabels_labels_tag_set,
                    tag_sets_label       => $nytlabels_labels_tag_set,
                    tag_sets_description => 'NYTLabels labels',

                    # e.g. "hurricanes and tropical storms"
                    tags_name        => $label,
                    tags_label       => $label,
                    tags_description => $label,
                }
            );
        }
        else
        {
            DEBUG "Skipping label '$label' because its score $score is lower than the threshold $NYTLABELS_SCORE_THRESHOLD";
        }
    }

    return $tags;
}

# Add NYTLabels version, country and story tags for story
sub update_nytlabels_tags_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( MediaWords::Util::NYTLabels::nytlabels_is_enabled() )
    {
        fatal_error( "NYTLabels annotator is not enabled in the configuration." );
    }

    my $config = MediaWords::Util::Config::get_config();

    my $nytlabels_version_tag = $config->{ nytlabels }->{ nytlabels_version_tag };
    unless ( $nytlabels_version_tag )
    {
        fatal_error( "NYTLabels version tag is unset in configuration." );
    }

    my $tags = [];

    push(
        @{ $tags },
        {
            tag_sets_name        => $NYTLABELS_VERSION_TAG_SET,
            tag_sets_label       => $NYTLABELS_VERSION_TAG_SET,
            tag_sets_description => 'NYTLabels version the story was tagged with',

            tags_name        => $nytlabels_version_tag,
            tags_label       => $nytlabels_version_tag,
            tags_description => "Story was tagged with '$nytlabels_version_tag'",
        }
    );

    my $annotation = MediaWords::Util::NYTLabels::fetch_annotation_for_story( $db, $stories_id );
    unless ( $annotation )
    {
        die "Unable to fetch NYTLabels annotation for story $stories_id";
    }

    unless ( ref( $annotation ) eq ref( {} ) )
    {
        die "NYTLabels annotation is not a hashref for story $stories_id; annotation: " . Dumper( $annotation );
    }

    my $nytlabels_tags = _tags_for_nytlabels_annotation( $annotation );
    push( @{ $tags }, @{ $nytlabels_tags } );

    DEBUG "NYTLabels tags for story $stories_id: " . Dumper( $tags );

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
