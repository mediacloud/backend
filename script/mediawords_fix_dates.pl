#!/usr/bin/env perl

# given a list of stories_ids, re-guess the date and assign the new guess if the method is not source_link

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::TM::Mine;

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    while ( my $line = <> )
    {
        my $stories_id = int( $line );

        my $story = $db->require_by_id( 'stories', $stories_id );

        my $content_ref = MediaWords::DBI::Stories::fetch_content( $db, $story );

        WARN( "STORY $story->{ stories_id }" );

        if ( !$$content_ref )
        {
            warn( "unable to fetch content for story $story->{ stories_id }" );
            next;
        }

        my ( $method, $date ) = MediaWords::TM::Mine::get_new_story_date( $db, $story, $$content_ref );

        next if ( $method eq 'source_link' );

        WARN( "$date [$method]" );

        $db->begin;

        $db->update_by_id( 'stories', $stories_id, { publish_date => $date } );
        MediaWords::DBI::Stories::GuessDate::assign_date_guess_method( $db, $story, $method );

        $db->commit;
    }

    # my $fields = [ qw/stories_id publish_date guess_date guess_method title url collect_date media_id/ ];
    # print( MediaWords::Util::CSV::get_hashes_as_encoded_csv( $stories, $fields ) );

}

main();
