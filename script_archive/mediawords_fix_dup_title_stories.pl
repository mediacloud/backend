#!/usr/bin/env perl

# walk through scratch.dup_title_stories and remove duplicate stories,
# paying attention to 1) revector stories to make sure all sentences
# are present in the remaining stories and 2) make sure any dup controversy
# stories are properly merged

use strict;
use warnings;

use Data::Dumper;
use Sys::RunAlone;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::StoryVectors;

sub delete_dup_story_list
{
    my ( $db, $dup_story_list ) = @_;

    $db->query( "delete from scratch.dup_title_stories where dup_title_stories_id = ?",
        $dup_story_list->{ dup_title_stories_id } );
}

sub is_dup_story_list_artifact
{
    my ( $db, $dup_story_list ) = @_;

    my $stories_ids = $dup_story_list->{ stories_ids };

    return 0 unless ( @{ $stories_ids } == 2 );

    my $twelve_hours = $db->query( <<END, @{ $stories_ids } )->hash;
select 1 from stories
    where stories_id in ( ?, ? )
    having max( publish_date ) - min( publish_date ) > interval '12 hours'
END

    return '12 hours' if ( $twelve_hours );

    my $feed_types = $db->query( <<END, @{ $stories_ids } )->hashes;
select distinct( f.feed_type ) feed_type
    from stories s
        join feeds_stories_map fsm on ( s.stories_id = fsm.stories_id )
        join feeds f on ( f.feeds_id = fsm.feeds_id )
    where s.stories_id in ( ?, ? )
END

    return 'web page feed' if ( ( @{ $feed_types } == 1 ) && ( $feed_types->[ 0 ]->{ feed_type } eq 'web_page' ) );

    return 0;
}

sub get_first_stories_id
{
    my ( $db, $stories_ids ) = @_;

    my $stories_ids_list = join( ',', @{ $stories_ids } );

    my ( $stories_id ) = $db->query( <<END )->flat;
select stories_id from stories where stories_id in ( $stories_ids_list ) limit 1
END

    return $stories_id;
}

sub fix_dup_story_list
{
    my ( $db, $dup_story_list ) = @_;

    say STDERR "dedupping $dup_story_list->{ media_id } [$dup_story_list->{ date_trunc }]: $dup_story_list->{ title }";

    my $stories_ids = $dup_story_list->{ stories_ids };

    my $stories_ids_list = join( ',', @{ $stories_ids } );

    my $first_stories_id = get_first_stories_id( $db, $stories_ids );

    if ( ( my $dup = is_dup_story_list_artifact( $db, $dup_story_list ) ) || !$first_stories_id )
    {
        say STDERR "skipping: $dup";
        delete_dup_story_list( $db, $dup_story_list );
        return;
    }

    my $controversy_stories_ids = $db->query( <<END )->hashes;
select distinct( stories_id ) stories_id from controversy_stories where stories_id in ( $stories_ids_list );
END

    if ( @{ $controversy_stories_ids } > 1 )
    {
        warn( "more than one distinct story in a controversy: " . Dumper( $dup_story_list ) );
        $db->query( <<END, $dup_story_list->{ dup_title_stories_id } );
update scratch.dup_title_stories set skip='t' where dup_title_stories_id = ?
END
        return;
    }

    my $keep_stories_id =
      @{ $controversy_stories_ids } ? $controversy_stories_ids->[ 0 ]->{ stories_id } : $first_stories_id;

    $db->query( "delete from story_sentence_counts where first_stories_id in ( $stories_ids_list )" );
    $db->query( "delete from stories where stories_id in ( $stories_ids_list ) and stories_id <> $keep_stories_id" );

    my $keep_story = $db->find_by_id( 'stories', $keep_stories_id )
      || die( "unable to find keep story $keep_stories_id" . Dumper( $dup_story_list ) );

    MediaWords::StoryVectors::update_story_sentence_words_and_language( $db, $keep_story );

    delete_dup_story_list( $db, $dup_story_list );

    $db->commit;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;
    $db->dbh->{ AutoCommit } = 0;

    while ( 1 )
    {
        my $dup_stories = $db->query( <<END )->hashes;
select * from scratch.dup_title_stories where not ( skip = 't' ) order by date_trunc desc limit 1000
END

        last unless ( $dup_stories );

        for my $dup_story_list ( @{ $dup_stories } )
        {
            fix_dup_story_list( $db, $dup_story_list );
        }
    }

}

main();

__END__
