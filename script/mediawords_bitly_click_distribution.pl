#!/usr/bin/env perl
#
# Bit.ly click distribution histogram
#
# Usage:
# ./script/run_with_carton.sh ./script/mediawords_bitly_click_distribution.pl [--limit 200] > bitly_click_distrib.csv
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
use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::Util::DateTime;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

use Getopt::Long;
use Readonly;
use DateTime;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $limit = 200;

    Readonly my $usage => <<"EOF";
Usage: $0 [--limit $limit]
EOF

    Getopt::Long::GetOptions( 'limit=i' => \$limit, ) or die $usage;

    my $db = MediaWords::DB::connect_to_db;

    my $publish_timestamp_lower_bound = DateTime->new( year => 2008, month => 01, day => 01 )->epoch;

    # Subtract the 150 days
    my $publish_timestamp_upper_bound = DateTime->now()->epoch - ( 60 * 60 * 24 * 150 );

    # Hour offset since "publish_date" buckets for generating the histogram
    my $from_day_offset = -31;
    my $to_day_offset   = 31;
    my $buckets         = [];
    for ( my $day_offset = $from_day_offset ; $day_offset <= $to_day_offset ; ++$day_offset )
    {
        my $bucket;
        my $hour_offset = $day_offset * 24;
        if ( $day_offset == $from_day_offset )
        {
            $bucket = { from => undef, to => $hour_offset };
        }
        elsif ( $day_offset == $to_day_offset )
        {
            $bucket = { from => $hour_offset + 1, to => undef };
        }
        else
        {
            $bucket = { from => $hour_offset - 24 + 1, to => $hour_offset };
        }

        push( @{ $buckets }, $bucket );
    }

    say STDERR "Fetching (up to) $limit stories...";
    my $stories = $db->query(
        <<EOF,
        SELECT *
        FROM stories
        WHERE stories_id IN (
            SELECT stories_id
            FROM controversy_stories
                INNER JOIN controversies
                    ON controversy_stories.controversies_id = controversies.controversies_id
            WHERE controversies.process_with_bitly = 't'
            ORDER BY RANDOM()
            LIMIT ?
        )
        ORDER BY stories_id
EOF
        $limit
    )->hashes;

    my $min_publish_timestamp = undef;
    my $max_publish_timestamp = undef;

    my $story_count = 1;
    foreach my $story ( @{ $stories } )
    {
        my $stories_id           = $story->{ stories_id };
        my $stories_url          = $story->{ url };
        my $stories_publish_date = $story->{ publish_date };

        say STDERR "\nProcessing story $stories_id ($story_count / " . scalar( @{ $stories } ) . ")...";
        ++$story_count;

        unless ( $stories_url )
        {
            say STDERR "URL is unset for story $stories_id";
            next;
        }
        unless ( MediaWords::Util::URL::is_http_url( $stories_url ) )
        {
            say STDERR "URL '$stories_url' is not a http(s) URL for story $stories_id";
            next;
        }

        unless ( $stories_publish_date )
        {
            say STDERR "Publish date is unset for story $stories_id";
            next;
        }

        my $publish_timestamp = MediaWords::Util::SQL::get_epoch_from_sql_date( $stories_publish_date );
        if ( $publish_timestamp <= $publish_timestamp_lower_bound )
        {
            say STDERR "Publish timestamp is lower than the lower bound for story $stories_id";
            next;
        }
        if ( $publish_timestamp >= $publish_timestamp_upper_bound )
        {
            say STDERR "Publish timestamp is bigger than the upper bound for story $stories_id";
            next;
        }

        # Round timestamp to the nearest day because that's what Bitly.pm does
        my $publish_datetime = gmt_datetime_from_timestamp( $publish_timestamp );
        $publish_datetime->set( hour => 0, minute => 0, second => 0 );
        $publish_timestamp = $publish_datetime->epoch;

        $min_publish_timestamp = $publish_timestamp
          if !defined $min_publish_timestamp or $min_publish_timestamp > $publish_timestamp;
        $max_publish_timestamp = $publish_timestamp
          if !defined $max_publish_timestamp or $max_publish_timestamp < $publish_timestamp;

        # Span across ~300 days
        my $start_timestamp = $publish_timestamp - ( 60 * 60 * 24 * 150 );
        my $end_timestamp   = $publish_timestamp + ( 60 * 60 * 24 * 150 );

        # How many seconds to sleep between rate limiting errors
        Readonly my $BITLY_RATE_LIMIT_SECONDS_TO_WAIT => 60 * 10;    # every 10 minutes

        # How many times to try on rate limiting errors
        Readonly my $BITLY_RATE_LIMIT_TRIES => 7;                    # try fetching 7 times in total (70 minutes)

        # What stats to fetch for each story
        Readonly my $BITLY_FETCH_CATEGORIES => 0;
        Readonly my $BITLY_FETCH_CLICKS     => 1;
        Readonly my $BITLY_FETCH_REFERRERS  => 0;
        Readonly my $BITLY_FETCH_SHARES     => 0;
        Readonly my $stats_to_fetch         => MediaWords::Util::Bitly::StatsToFetch->new(
            $BITLY_FETCH_CATEGORIES,                                 # "/v3/link/category"
            $BITLY_FETCH_CLICKS,                                     # "/v3/link/clicks"
            $BITLY_FETCH_REFERRERS,                                  # "/v3/link/referrers"
            $BITLY_FETCH_SHARES                                      # "/v3/link/shares"
        );

        my $story_stats = undef;
        my $retry       = 0;
        my $error_message;
        do
        {
            say STDERR "Fetching story stats for story $stories_id" . ( $retry ? " (retry $retry)" : '' ) . "...";
            eval {
                $story_stats = MediaWords::Util::Bitly::fetch_stats_for_url( $db, $stories_url,
                    $start_timestamp, $end_timestamp, $stats_to_fetch );
            };
            $error_message = $@;

            if ( $error_message )
            {
                if ( MediaWords::Util::Bitly::error_is_rate_limit_exceeded( $error_message ) )
                {
                    say STDERR "Rate limit exceeded while collecting story stats for story $stories_id";
                    say STDERR "Sleeping for $BITLY_RATE_LIMIT_SECONDS_TO_WAIT before retrying";
                    sleep( $BITLY_RATE_LIMIT_SECONDS_TO_WAIT + 0 );
                }
                else
                {
                    die "Error while collecting story stats for story $stories_id: $error_message";
                }
            }
            ++$retry;
        } until ( $retry > $BITLY_RATE_LIMIT_TRIES + 0 or ( !$error_message ) );

        unless ( $story_stats )
        {
            # No point die()ing and continuing with other jobs (didn't recover after rate limiting)
            die "Stats for story ID $stories_id is undef (after $retry retries).";
        }
        unless ( ref( $story_stats ) eq ref( {} ) )
        {
            # No point die()ing and continuing with other jobs (something wrong with fetch_stats_for_story())
            die "Stats for story ID $stories_id is not a hashref.";
        }
        say STDERR "Done fetching story stats for story $stories_id.";

        foreach my $bitly_hash ( keys %{ $story_stats->{ data } } )
        {
            foreach my $bitly_clicks ( @{ $story_stats->{ data }->{ $bitly_hash }->{ clicks } } )
            {
                foreach my $link_click ( @{ $bitly_clicks->{ link_clicks } } )
                {
                    my $clicks     = $link_click->{ clicks } + 0;
                    my $dt         = $link_click->{ dt } + 0;
                    my $diff       = $dt - $publish_timestamp;
                    my $diff_hours = int( $diff / 60 / 60 );

                    if ( $clicks > 0 )
                    {
                        my $bucket_found = 0;
                        foreach my $bucket ( @{ $buckets } )
                        {
                            my $bucket_from = $bucket->{ from };
                            my $bucket_to   = $bucket->{ to };

                            unless ( defined $bucket->{ clicks } )
                            {
                                $bucket->{ clicks } = 0;
                            }

                            if ( ( !defined( $bucket_from ) ) or $bucket_from <= $diff_hours )
                            {
                                if ( ( !defined( $bucket_to ) ) or $bucket_to >= $diff_hours )
                                {

                                    if ( $bucket_found )
                                    {
                                        die "More than one bucket was found for hours $diff_hours";
                                    }
                                    else
                                    {
                                        $bucket_found = 1;
                                    }

                                    $bucket->{ clicks } += $clicks;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    say STDERR "Min. publish timestamp: $min_publish_timestamp";
    say STDERR "Max. publish timestamp: $max_publish_timestamp";

    say '"Hours since \'publish_date\'","Clicks"';
    foreach my $bucket ( @{ $buckets } )
    {
        print '"';
        print( $bucket->{ from } // 'inf' );
        print ' -- ';
        print( $bucket->{ to } // 'inf' );
        print '",' . $bucket->{ clicks } . "\n";
    }

    say STDERR "Done.";
}

main();
