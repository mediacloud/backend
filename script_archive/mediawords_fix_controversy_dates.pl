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
use MediaWords::CM::GuessDate::Result;
use MediaWords::DBI::Stories;
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

# assign a tag to the story for the date guess method
sub assign_date_guess_method
{
    my ( $db, $story, $date_guess_method ) = @_;

    my $date_guess_method_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "date_guess_method:$date_guess_method" );

    $db->query( <<END, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t, tag_sets ts
    where stm.tags_id = t.tags_id and t.tag_sets_id = ts.tag_sets_id and 
        ts.name = 'date_guess_method' and stm.stories_id = ?    
END

    $db->create( 'stories_tags_map',
        { stories_id => $story->{ stories_id }, tags_id => $date_guess_method_tag->{ tags_id } } );
}

# guess the date for the story and update it in the db
sub fix_date
{
    my ( $db, $story, $controversy ) = @_;

    my $html_ref = MediaWords::DBI::Stories::get_initial_download_content( $db, $story );

    my $linking_story = $db->query( <<'END', $story->{ stories_id }, $controversy->{ controversies_id } )->hash;
select s.*
    from stories s
        join controversy_links cl on ( cl.controversies_id = $2 and s.stories_id = cl.stories_id )
    where 
        cl.ref_stories_id = $1
    order by cl.controversy_links_id
END

    my $use_threshold = 0;
    if ( $linking_story )
    {
        $story->{ publish_date } = $linking_story->{ publish_date };
        $use_threshold = 1;
    }

    my $date = MediaWords::CM::GuessDate::guess_date( $db, $story, ${ $html_ref }, $use_threshold );

    if ( $date->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
    {
        $db->query( "update stories set publish_date = ? where stories_id = ?", $date->{ date }, $story->{ stories_id } );
        assign_date_guess_method( $db, $story, $date->{ guess_method } );
        print STDERR "$story->{ url }\t$story->{ publish_date }\t$date->{ date }\t$date->{ guess_method }\n";
    }
    elsif ( $date->{ result } eq MediaWords::CM::GuessDate::Result::INAPPLICABLE )
    {
        assign_date_guess_method( $db, $story, 'undateable' );
        print STDERR "$story->{ url }\t$story->{ publish_date }\tundateable\n";
    }
    else
    {
        $date->{ date } = $date->{ method } = '(no guess)';
        print STDERR "$story->{ url }\t$story->{ publish_date }\tno guess\n";
    }

}

# get all sopa stories
sub get_controversy_stories
{
    my ( $db, $controversy ) = @_;

    print STDERR "getting stories ...\n";

    my $stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select distinct s.* 
    from stories s 
        join controversy_stories cs on ( s.stories_id = cs.stories_id and cs.controversies_id = ? ) 
        join stories_tags_map stm on ( s.stories_id = stm.stories_id ) 
        join tags t on ( t.tags_id = stm.tags_id and 
            t.tag not in ( 'merged_story_rss', 'guess_by_url_and_date_text', 'guess_by_url' ) ) join 
        tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'date_guess_method' )
END

    return $stories;
}

sub main
{
    my ( $controversies_id ) = @ARGV;

    die( "usage: $0 < controversies_id >" ) unless ( $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    my $stories = get_controversy_stories( $db, $controversy );

    map { fix_date( $db, $_, $controversy ) } @{ $stories };

}

main();
