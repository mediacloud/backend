#!/usr/bin/env perl

# use the TM::Mine::get_new_story_date to guess the date of the given story

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
use MediaWords::TM::Mine;

sub main
{
    my ( $stories_id ) = @ARGV;

    die( "usage: $0 < stories_id >" ) unless ( $stories_id );

    my $db = MediaWords::DB::connect_to_db();

    # my $story = $db->query( "select * from stories where stories_id = ?", $stories_id )->hash;
    #die( "story '$stories_id' not found" ) unless ( $story );

    my $stories = $db->query( <<SQL )->hashes;
select s.* from stories s join scratch.sl_stories ss using ( stories_id ) order by random() limit 1000
SQL

    for my $story ( @{ $stories } )
    {
        my $content_ref = MediaWords::DBI::Stories::fetch_content( $db, $story );

        WARN( "STORY $story->{ stories_id }" );

        if ( !$$content_ref )
        {
            warn( "unable to fetch content for story $story->{ stories_id }" );
            next;
        }

        my ( $method, $date ) = MediaWords::TM::Mine::get_new_story_date( $db, $story, $$content_ref );

        $story->{ guess_method } = $method;
        $story->{ guess_date }   = $date;
    }

    my $fields = [ qw/stories_id publish_date guess_date guess_method title url collect_date media_id/ ];
    print( MediaWords::Util::CSV::get_hashes_as_encoded_csv( $stories, $fields ) );

}

main();
