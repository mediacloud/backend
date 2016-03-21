#!/usr/bin/env perl

# given a list of twitter users, fetch the favorites_count and retweet_count stats for the most recent
# tweets from each user

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";

use Net::Twitter;

use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Util::Config;

# get the engagement score for the user, which is just the sum of the favorite_count and retweet_count for
# the last 200 tweets
sub print_user_engagement
{
    my ( $twitter, $user ) = @_;

    if ( $user eq 'NONE FOUND' )
    {
        say 'NONE FOUND,0,0';
        return;
    }

    my $tweets;
    eval { $tweets = $twitter->user_timeline( { screen_name => $user, count => 3200 } ) };
    if ( $@ )
    {
        if ( $@ =~ /^Sorry, that page does not exist./ )
        {
            say "$user,0,0";
            return;
        }
        elsif ( $@ =~ /^Rate limit exceeded/ )
        {
            # my $limit = $twitter->rate_limit_status;
            # say STDERR Dumper( $limit );
            say STDERR "rate limit execeeded.  sleeping for 90 seconds ...";
            sleep( 90 );
            print_user_engagement( $twitter, $user );
            return;
        }
        else
        {
            die( "twitter api error: '$@'" );
        }
    }

    # print Dumper( $result );

    my $engagement = 0;
    my $count      = 0;
    for my $tweet ( @{ $tweets } )
    {
        if ( !$tweet->{ retweeted_status } && ( $count < 50 ) )
        {
            $engagement += $tweet->{ favorite_count } + $tweet->{ retweet_count };
            $count++;
        }
    }

    say "$user,$engagement,$count";
}

sub main
{
    $| = 1;
    binmode( STDOUT, 'utf8' );
    my $config = MediaWords::Util::Config::get_config;

    map { die( "missing config for twitter.$_" ) unless ( $config->{ twitter }->{ $_ } ) }
      qw(consumer_key consumer_secret access_token access_token_secret);

    my $twitter = Net::Twitter->new(
        traits              => [ qw/API::RESTv1_1/ ],
        consumer_key        => $config->{ twitter }->{ consumer_key },
        consumer_secret     => $config->{ twitter }->{ consumer_secret },
        access_token        => $config->{ twitter }->{ access_token },
        access_token_secret => $config->{ twitter }->{ access_token_secret },
    );

    while ( my $user = <> )
    {
        chomp( $user );
        print_user_engagement( $twitter, $user );
    }
}

main();
