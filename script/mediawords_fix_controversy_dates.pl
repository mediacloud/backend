#!/usr/bin/env perl

# Run through the controversy stories, trying to assign better date guesses

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use DateTime;
use LWP::UserAgent;

use MediaWords::CM::GuessDate;
use MediaWords::CM::Mine;
use MediaWords::DB;
use MediaWords::CM;
use MediaWords::DBI::Stories;

# guess the date for the story and update it in the db, using
sub fix_date
{
    my ( $db, $story, $controversy ) = @_;

    print STDERR "$story->{ url }\n";

    my $story_content = ${ MediaWords::DBI::Stories::fetch_content( $db, $story ) };

    my $source_link = $db->query( <<'END', $story->{ stories_id }, $controversy->{ controversies_id } )->hash;
select * from controversy_links where ref_stories_id = ? and controversies_id = ? order by controversy_links_id limit 1
END

    my ( $method, $date ) = MediaWords::CM::Mine::get_new_story_date( $db, $story, $story_content, undef, $source_link );

    $date =~ s/(\d)T(\d)/$1 $2/;

    return if ( $story->{ publish_date } eq $date );

    print STDERR "fix: $story->{ publish_date } -> $date [ $method ]\n";

    $db->query( "update stories set publish_date = ? where stories_id = ? ", $date, $story->{ stories_id } );

    MediaWords::DBI::Stories::assign_date_guess_method( $db, $story, $method );
}

# get controverys stories in need of redating
sub get_controversy_stories_to_date
{
    my ( $db, $controversy ) = @_;

    print STDERR "getting stories ...\n";

    my $stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select s.* from cd.live_stories s where s.controversies_id = ? limit 1000
END

    print STDERR "filtering for unreliable stories: ";
    my $unreliable_stories = [];
    for my $story ( @{ $stories } )
    {
        print STDERR ".";
        if ( !MediaWords::DBI::Stories::date_is_reliable( $db, $story ) )
        {
            push( @{ $unreliable_stories }, $story );
        }
    }

    print STDERR "\n";

    return $unreliable_stories;
}

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    my $db = MediaWords::DB::connect_to_db;

    my $controversies = MediaWords::CM::require_controversies_by_opt( $db );

    for my $controversy ( @{ $controversies } )
    {
        print "CONTROVERSY $controversy->{ name } \n";
        my $stories = get_controversy_stories_to_date( $db, $controversy );

        map { fix_date( $db, $_, $controversy ) } @{ $stories };
    }
}

main();

__END__
