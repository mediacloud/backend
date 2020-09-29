package MediaWords::DBI::Stories;

#
# Various helper functions for stories
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.stories.stories' );

use MediaWords::Util::SQL;
use MediaWords::Util::URL;

# common title prefixes that can be ignored for dup title matching
Readonly my $DUP_TITLE_PREFIXES => [
    qw/opinion analysis report perspective poll watch exclusive editorial reports breaking nyt/,
    qw/subject source wapo sources video study photos cartoon cnn today wsj review timeline/,
    qw/revealed gallup ap read experts op-ed commentary feature letters survey/
];

# Given two lists of hashes, $stories and $story_data, each with
# a stories_id field in each row, assign each key:value pair in
# story_data to the corresponding row in $stories.  If $list_field
# is specified, push each the value associate with key in each matching
# stories_id row in story_data field into a list with the name $list_field
# in stories.
#
# Return amended stories hashref.
sub attach_story_data_to_stories
{
    my ( $stories, $story_data, $list_field ) = @_;

    if ( $list_field ) {
        for my $story ( @{ $stories } ) {
            # This subroutine could be called for multiple "story_data" chunks
            # with the same "stories" list to attach the chunks to, so the list
            # with "list_field" key might already exist
            if ( defined $story->{ $list_field } ) {
                # Validate that it's actually an arrayref
                unless ( ref( $story->{ $list_field } ) eq ref( [] ) )  {
                    die "One or more stories already have '$list_field' set which is not an arrayref";
                }
            } else {
                $story->{ $list_field } = [];
            }
        }
    }

    unless ( scalar @{ $story_data } )
    {
        return $stories;
    }

    TRACE "stories size: " . scalar( @{ $stories } );
    TRACE "story_data size: " . scalar( @{ $story_data } );

    my $story_data_lookup = {};
    for my $sd ( @{ $story_data } )
    {
        my $sd_id = $sd->{ stories_id };
        if ( $list_field )
        {
            $story_data_lookup->{ $sd_id } //= { $list_field => [] };
            push( @{ $story_data_lookup->{ $sd_id }->{ $list_field } }, $sd );
        }
        else
        {
            $story_data_lookup->{ $sd_id } = $sd;
        }
    }

    for my $story ( @{ $stories } )
    {
        my $sid = $story->{ stories_id };
        if ( my $sd = $story_data_lookup->{ $sid } )
        {
            foreach my $story_key ( keys( %{ $sd } ) ) {
                if ( defined $list_field and $story_key eq $list_field ) {
                    $story->{ $story_key } //= [];
                    foreach my $story_field_value ( @{ $sd->{ $story_key } } ) {
                        push( @{ $story->{ $story_key } }, $story_field_value );
                    }
                } else {
                    $story->{ $story_key } = $sd->{ $story_key };
                }
            }

            TRACE "story matched: " . Dumper( $story );
        }
    }

    return $stories;
}

# Call attach_story_data_to_stories_ids with a basic query that includes the fields:
# stories_id, title, publish_date, url, guid, media_id, language, media_name.
#
# Return the updated stories arrayref.
sub attach_story_meta_data_to_stories
{
    my ( $db, $stories ) = @_;

    my $use_transaction = !$db->in_transaction();
    $db->begin if ( $use_transaction );

    my $ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ stories_id } ) } @{ $stories } ] );

    my $story_data = $db->query( <<END )->hashes;
select s.stories_id, s.title, s.publish_date, s.url, s.guid, s.media_id, s.language, m.name media_name
    from stories s join media m on ( s.media_id = m.media_id )
    where s.stories_id in ( select id from $ids_table )
END

    $stories = attach_story_data_to_stories( $stories, $story_data );

    $db->commit if ( $use_transaction );

    return $stories;
}

1;
