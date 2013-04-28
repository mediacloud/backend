#!/usr/bin/env perl

# look for duplicate stories within the controversy merge them after confirmation

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Util::SQL;

# given a story and its duplicate, merge the duplicate into the story
sub merge_dup_story
{
    my ( $db, $story, $dup_story ) = @_;

    print STDERR
      "merging $story->{ title } [ $story->{ stories_id } ] <- $dup_story->{ title } [ $dup_story->{ stories_id } ]\n";

    $db->query(
        "update controversy_links set ref_stories_id = ? where ref_stories_id = ?",
        $story->{ stories_id },
        $dup_story->{ stories_id }
    );

    $db->query( "delete from stories where stories_id = ?", $dup_story->{ stories_id } );
}

# find all cases of stories with the same title and the same media id and merge them
sub merge_duplicate_stories
{
    my ( $db, $stories, $controversy ) = @_;

    # lookup of stories to skip b/c they have already been merged
    my $merged_stories_map = {};

    for my $story ( @{ $stories } )
    {
        next if ( $merged_stories_map->{ $story->{ stories_id } } );

        next if ( length( $story->{ title } ) < 16 );

        my $dup_stories = $db->query(
            "select distinct s.* from stories s, controversy_stories cs where cs.stories_id = s.stories_id and " .
              "    s.media_id = ? and s.title = ? and s.stories_id <> ? and cs.controversies_id = ?",
            $story->{ media_id },
            $story->{ title },
            $story->{ stories_id },
            $controversy->{ controversies_id }
        )->hashes;
        for my $dup_story ( @{ $dup_stories } )
        {
            my $dup_story_epoch = MediaWords::Util::SQL::get_epoch_from_sql_date( $dup_story->{ publish_date } );
            my $story_epoch     = MediaWords::Util::SQL::get_epoch_from_sql_date( $story->{ publish_date } );

            if (   ( $dup_story_epoch < ( $story_epoch - ( 7 * 86400 ) ) )
                || ( $dup_story > ( $story_epoch + ( 7 * 86400 ) ) ) )
            {
                next if ( length( $story->{ title } ) < 32 );

                my $dup_story_url_no_p = $dup_story->{ url };
                my $story_url_no_p     = $story->{ url };
                $dup_story_url_no_p =~ s/(.*)\?(.*)/$1/;
                $story_url_no_p     =~ s/(.*)\?(.*)/$1/;

                next if ( lc( $dup_story_url_no_p ) ne lc( $story_url_no_p ) );
            }

            merge_dup_story( $db, $story, $dup_story );
            $merged_stories_map->{ $dup_story->{ stories_id } } = 1;
        }
    }
}

sub main
{
    my ( $controversies_id ) = @ARGV;

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->query( "select * from controversies where controversies_id = ?", $controversies_id )->hash
      || die( "Unable to find controversy '$controversies_id'" );

    my $stories = $db->query(
        "select * from stories s, controversy_stories cs " .
          "  where s.stories_id = cs.stories_id and cs.controversies_id = ?",
        $controversy->{ controversies_id }
    )->hashes;

    merge_duplicate_stories( $db, $stories );
}

main();
