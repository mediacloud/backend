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

use Modern::Perl "2013";

use MediaWords::CM;
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Util::Config;
use MediaWords::Util::JSON;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;

use Text::CSV;
use URI;

# get the ch api key from the config
sub get_ch_key
{
    my $config = MediaWords::Util::Config::get_config;

    my $ch_key = $config->{ crimson_hexagon }->{ api_key };
    die( "missing crimson hexagon api key" ) unless ( $ch_key );

    return $ch_key;
}

# call the ch api to get the tweets for the given day
sub get_data_from_ch
{
    my ( $monitor_id, $day ) = @_;

    say STDERR "fetching data for $day ...";

    my $ch_key = get_ch_key();

    my $cgi_args = {
        auth        => $ch_key,
        id          => $monitor_id,
        start       => $day,
        end         => MediaWords::Util::SQL::increment_day( $day ),
        extendLimit => 'true',
    };

    my $ch_url = 'https://api.crimsonhexagon.com/api/monitor/posts';

    my $uri = URI->new( $ch_url );
    $uri->query_form( $cgi_args );

    my $ua = MediaWords::Util::Web::UserAgentDetermined();
    $ua->max_size( undef );

    # UserAgentDetermined will retry on server-side errors; client-side errors
    # will be handled by this module
    $ua->timing( '1,3,15,60,300,600' );

    my $response;
    eval { $response = $ua->get( $uri ) };
    if ( $@ )
    {
        die 'LWP::UserAgent::Determined died while fetching response: ' . $@;
    }

    die( "ch request failed for $monitor_id / $day: " . $response->as_string ) if ( $response->{ is_success } );

    my $decoded_content = $response->decoded_content;

    my $data = MediaWords::Util::JSON::decode_json( $decoded_content );

    return $data;
}

sub get_controversy_days
{
    my ( $db, $controversy ) = @_;

    my $days = [];
    my $day  = $controversy->{ start_date };
    while ( $day le $controversy->{ end_date } )
    {
        push( @{ $days }, $day );
        $day = MediaWords::Util::SQL::increment_day( $day, 1 );
    }

    return $days;
}

# create controversy_tweet_search for the given search and day
sub create_controversy_tweet_search
{
    my ( $db, $controversy, $monitor_id, $day, $tweet_count ) = @_;

    my $end_date = MediaWords::Util::SQL::increment_day( $day, 1 );

    my $cts = {
        controversies_id => $controversy->{ controversies_id },
        ch_monitor_id    => $monitor_id,
        start_date       => $day,
        end_date         => $day,
        tweet_count      => $tweet_count
    };

    return $db->create( 'controversy_tweet_searches', $cts );
}

# give a list of posts returned from the ch api, return a list of tweet ids by parsing
# the ids out of the tweet status urls
sub get_tweet_ids
{
    my ( $posts ) = @_;

    my $ids = [];
    for my $post ( @{ $posts } )
    {
        my $url = $post->{ url };

        if ( !( $url =~ m~http://twitter.com/\w+/status/(\d+)~ ) )
        {
            die( "can't parse tweet url: $url" );
        }

        push( @{ $ids }, $1 );
    }

    return $ids;
}

sub create_controversy_tweet
{
    my ( $db, $cts, $tweet_id ) = @_;

}

# use copy to insert tweets en masse
sub insert_tweets
{
    my ( $db, $cts, $tweet_ids ) = @_;

    my $fields = [ qw/controversy_tweet_searches_id tweet_id/ ];
    my $field_list = join( ',', @{ $fields } );

    my $copy = <<END;
copy controversy_tweets ( $field_list ) from STDIN with csv
END
    eval { $db->dbh->do( $copy ) };
    die( " Error on copy: $@" ) if ( $@ );

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    for my $tweet_id ( @{ $tweet_ids } )
    {
        $csv->combine( $cts->{ controversy_tweet_searches_id }, $tweet_id );
        eval { $db->dbh->pg_putcopydata( $csv->string . "\n" ) };

        die( " Error on pg_putcopydata: $@" ) if ( $@ );
    }

    eval { $db->dbh->pg_putcopyend() };

    die( " Error on pg_putcopyend: $@" ) if ( $@ );
}

# fetch results of a single day of tweets from ch.  store tweets and resulting search.
sub fetch_and_store_day
{
    my ( $db, $controversy, $monitor_id, $day ) = @_;

    say STDERR "fetch results for $controversy->{ controversies_id } / $day";

    my $ret = get_data_from_ch( $monitor_id, $day );

    my $tweet_ids   = get_tweet_ids( $ret->{ posts } );
    my $tweet_count = $ret->{ totalPostsAvailable };

    $db->begin;

    my $cts = create_controversy_tweet_search( $db, $controversy, $monitor_id, $day, $tweet_count );

    insert_tweets( $db, $cts, $tweet_ids );

    $db->commit;

    say STDERR "tweets: $tweet_count found, " . scalar( @{ $tweet_ids } ) . " returned";
}

# return true if the given tweet search already exists
sub controversy_tweet_search_exists
{
    my ( $db, $controversy, $monitor_id, $day ) = @_;

    my $cts = $db->query( <<SQL, $controversy->{ controversies_id }, $day )->hash;
select *
    from controversy_tweet_searches
    where
        controversies_id = \$1 and
        start_date = \$2 and
        end_date = \$2
SQL
}

# given a controversy and a ch monitor id, create as necessary a controversy_tweet_search
# for each day in the date range of the controversy and controversy_tweets for each tweet
# return by each day of tweets as returned by ch
sub fetch_and_store_controversy_tweets
{
    my ( $db, $controversy, $monitor_id ) = @_;

    my $days = get_controversy_days( $db, $controversy );
    for my $day ( @{ $days } )
    {
        next if ( controversy_tweet_search_exists( $db, $controversy, $day ) );
        fetch_and_store_day( $db, $controversy, $monitor_id, $day );
    }
}

sub main
{
    $| = 1;
    binmode( STDOUT, 'utf8' );

    my ( $monitor_id, $controversy_opt );
    Getopt::Long::GetOptions(
        "controversy=s" => \$controversy_opt,
        "monitor_id=s"  => \$monitor_id,
    ) || return;

    die( "usage: $0 --controversy < id > --monitor_id <id>" ) unless ( $controversy_opt && $monitor_id );

    my $db = MediaWords::DB::connect_to_db;

    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );
    unless ( $controversies )
    {
        die "Unable to find controversies for option '$controversy_opt'";
    }

    for my $controversy ( @{ $controversies } )
    {
        fetch_and_store_controversy_tweets( $db, $controversy, $monitor_id );
    }
}

main();
