#!/usr/bin/env perl
#
# Enqueue stories for Bit.ly processing.
#
# It is safe to run this as many times as you want because the extraction job
# on Gearman is unique so stories won't be duplicated.
#
# Usage:
#
#     mediawords_enqueue_stories_for_bitly_on_gearman.pl
#
# Define environment variable VERBOSE=1 to see more debugging strings about what's happening.
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use MediaWords::Util::Bitly;
use MediaWords::GearmanFunction::Bitly::FetchStoryStats;
use DateTime;

# Returns true if verbose output should be used
sub _verbose
{
    return ( exists $ENV{ 'VERBOSE' } and $ENV{ 'VERBOSE' } eq '1' );
}

# Enqueue stories for Bit.ly processing
sub enqueue_stories_to_bitly()
{
    Readonly my $overwrite_annotations => 1;
    Readonly my $chunk_size            => 100;

    # FIXME
    Readonly my $start_timestamp => DateTime->new(
        year      => 2014,
        month     => 8,
        day       => 1,
        hour      => 0,
        minute    => 0,
        second    => 0,
        time_zone => 'Etc/GMT'
    )->epoch();
    Readonly my $end_timestamp => DateTime->new(
        year      => 2014,
        month     => 8,
        day       => 20,
        hour      => 0,
        minute    => 0,
        second    => 0,
        time_zone => 'Etc/GMT'
    )->epoch();

    my $db = MediaWords::DB::connect_to_db;

    say STDERR "Fetching stories..." if ( _verbose() );

    my $stories = $db->query(
        <<"EOF"
        SELECT stories_id
        FROM stories
        ORDER BY stories_id
        LIMIT $chunk_size
EOF
    )->hashes;
    say STDERR "Done fetching stories." if ( _verbose() );

    say STDERR "Number of results: " . scalar( @{ $stories } ) if ( _verbose() );

    last unless ( scalar( @{ $stories } ) > 0 );    # no stories

    foreach my $story ( @{ $stories } )
    {
        my $stories_id = $story->{ stories_id };

        say STDERR "Will attempt to enqueue story " . $stories_id if ( _verbose() );

        # MediaWords::GearmanFunction::Bitly::FetchStoryStats->enqueue_on_gearman( {
        MediaWords::GearmanFunction::Bitly::FetchStoryStats->run_locally(
            {
                stories_id      => $stories_id,
                start_timestamp => $start_timestamp,
                end_timestamp   => $end_timestamp
            }
        );

        say STDERR "Done enqueuing story " . $stories_id if ( _verbose() );
    }
}

sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    say STDERR "starting --  " . localtime();

    enqueue_stories_to_bitly ();

    say STDERR "finished --  " . localtime();
}

main();
