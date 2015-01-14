#!/usr/bin/env perl

#
# fetch twitter and facebook statistics for all stories in a controversy
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::DB;
use MediaWords::CM;
use MediaWords::Util::Twitter;
use MediaWords::Util::Facebook;

sub main
{
    my $controversy_opt;

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt ) || return;

    die( "Usage: $0 --controversy < id >" ) unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db;
    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );
    unless ( $controversies )
    {
        die "Unable to find controversies for option '$controversy_opt'";
    }

    for my $controversy ( @{ $controversies } )
    {
        my $controversies_id = $controversy->{ controversies_id };

        my $stories = $db->query( <<END, $controversies_id )->hashes;
    select s.stories_id, s.url
        from stories s
            join controversy_stories cs on ( cs.stories_id = s.stories_id )
        where
            cs.controversies_id = ?
END

        if ( !@{ $stories } )
        {
            say STDERR "No stories found for controversy '$controversy->{ name }' ('$controversy_opt')";
        }

        for my $story ( @{ $stories } )
        {

            my $ss = $db->query( "select * from story_statistics where stories_id = ?", $story->{ stories_id } )->hash;

            say STDERR "$story->{ url }";

            if ( !$ss || $ss->{ twitter_url_tweet_count_error } || !defined( $ss->{ twitter_url_tweet_count } ) )
            {
                my $count = MediaWords::Util::Twitter::get_and_store_tweet_count( $db, $story );
                say STDERR "url_tweet_count: $count";
            }

            # if ( !$ss || $ss->{ facebook_share_count_error} || !defined( $ss->{ facebook_share_count } ) )
            # {
            #     my $count = MediaWords::Util::Facebook::get_and_store_share_count( $db, $story );
            #     say STDERR "facebook_share_count: $count";
            # }
        }
    }
}

main();
