#!/usr/bin/env perl

# Run through the sopa stories, trying to assign better date guesses

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use DateTime;
use MediaWords::CM::GuessDate;
use MediaWords::CM::GuessDate::Result;
use LWP::UserAgent;

use MediaWords::DB;

# get the html for the story.  while downloads are not available, redownload the story.
sub get_story_html
{
    my ( $db, $story ) = @_;

    my $url = $story->{ redirect_url } || $story->{ url };

    my $ua = LWP::UserAgent->new;

    my $response = $ua->get( $url );

    if ( $response->is_success )
    {
        return $response->decoded_content;
    }
    else
    {
        return undef;
    }
}

# guess the date for the story and update it in the db
sub fix_date
{
    my ( $db, $story ) = @_;

    my $date = MediaWords::CM::GuessDate::guess_date( $db, $story );
    if ( $date->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
    {
        $db->query( "update stories set publish_date =  ? where stories_id = ?", $date->{ date }, $story->{ stories_id } );
    }
    else
    {
        $date = '(no guess)';
    }

    print "$story->{ url }\t$story->{ publish_date }\t$date_string\n";

}

# get all sopa stories
sub get_sopa_stories
{
    my ( $db ) = @_;

    my $stories = $db->query(
        "select distinct s.*, ss.redirect_url, md5( ( s.stories_id + 1 )::text ) from stories s, sopa_stories ss " .
          "  where s.stories_id = ss.stories_id " . "    and s.stories_id in " .
"      ( ( select stories_id from sopa_links_cross_media ) union ( select ref_stories_id from sopa_links_cross_media ) ) "
          .

          #        "  order by md5( ( s.stories_id + 1 )::text ) limit 100"
          "  order by stories_id "
    )->hashes;

    return $stories;
}

sub main
{
    test_date_parsers();

    my $db = MediaWords::DB::connect_to_db;

    my $stories = get_sopa_stories( $db );

    map { fix_date( $db, $_ ) } @{ $stories };

}

main();
