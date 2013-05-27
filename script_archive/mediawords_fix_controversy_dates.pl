#!/usr/bin/env perl

# Run through the controversy stories, trying to assign better date guesses

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use DateTime;
use MediaWords::CM::GuessDate;
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
    if ( defined( $date ) )
    {
        $db->query( "update stories set publish_date = ? where stories_id = ?", $date, $story->{ stories_id } );
    }
    else
    {
        $date = '(no guess)';
    }

    print "$story->{ url }\t$story->{ publish_date }\t$date_string\n";

}

# get all sopa stories
sub get_controversy_stories
{
    my ( $db, $controversy ) = @_;

    my $cid = $controversy->{ controversies_id };

    my $stories = $db->query(
        "select distinct s.*, cs.redirect_url, md5( ( s.stories_id + 1 )::text ) from stories s, controversy_stories cs " .
          "  where s.stories_id = cs.stories_id and cs.controversies_id = ?" . "    and s.stories_id in " .
          "      ( ( select stories_id from controversy_links_cross_media where controversies_id = ? ) union " .
          "        ( select ref_stories_id from controversy_links_cross_media where controversies_id = ? ) ) " .
          "    and s.stories_id > 88745132 " .

          #        "  order by md5( ( s.stories_id + 1 )::text ) limit 100"
          "  order by stories_id ",
        $cid, $cid, $cid
    )->hashes;

    return $stories;
}

sub main
{
    my ( $controversies_id ) = @ARGV;

    die( "usage: $0 < controversies_id >" ) unless ( $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    test_date_parsers();

    my $stories = get_controversy_stories( $db, $controversy );

    map { fix_date( $db, $_ ) } @{ $stories };

}

main();
