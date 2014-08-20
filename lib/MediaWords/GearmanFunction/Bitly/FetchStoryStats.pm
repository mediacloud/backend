package MediaWords::GearmanFunction::Bitly::FetchStoryStats;

#
# Fetch story's click / referrer count statistics via Bit.ly API
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/Bitly/FetchStoryStats.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::GearmanFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::Util::Process;
use Readonly;
use Data::Dumper;
use DateTime;
use Scalar::Defer;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

Readonly my $BITLY_FETCH_CATEGORIES => 0;
Readonly my $BITLY_FETCH_CLICKS     => 1;
Readonly my $BITLY_FETCH_REFERRERS  => 1;
Readonly my $BITLY_FETCH_SHARES     => 0;

# (Lazy-initialized) MongoDB GridFS key-value store
# We use a static, package-wide variable here because:
# a) MongoDB handler should support being used by multiple threads by now, and
# b) each Gearman worker is a separate process so there shouldn't be any resource clashes.
my $_gridfs_store = lazy
{
    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        fatal_error( "Bit.ly processing is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config->get_config();

    # GridFS storage
    my $gridfs_database_name = $config->{ mongodb_gridfs }->{ corenlp }->{ database_name };
    unless ( $gridfs_database_name )
    {
        fatal_error( "CoreNLP annotator is enabled, but MongoDB GridFS database name is not set." );
    }

    my $gridfs_store = MediaWords::KeyValueStore::GridFS->new( { database_name => $gridfs_database_name } );
    say STDERR "Will write CoreNLP annotator results to GridFS database: $gridfs_database_name";

    return $gridfs_store;
};

sub _fetch_story_stats($$$$)
{
    my ( $db, $stories_id, $start_timestamp, $end_timestamp ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Story ID $stories_id was not found.";
    }

    my $stories_url = $story->{ url };
    unless ( $stories_url )
    {
        die "Story URL for story ID $stories_id is empty.";
    }

    my $string_start_date = DateTime->from_epoch( epoch => $start_timestamp, time_zone => 'Etc/GMT' )->date();
    my $string_end_date   = DateTime->from_epoch( epoch => $end_timestamp,   time_zone => 'Etc/GMT' )->date();

    my $link_lookup;
    eval { $link_lookup = MediaWords::Util::Bitly::bitly_link_lookup_hashref_all_variants( $stories_url ); };
    if ( $@ or ( !$link_lookup ) )
    {
        die "Unable to lookup story ID $stories_id with URL $stories_url: $@";
    }

    say STDERR "Link lookup: " . Dumper( $link_lookup );

    # Fetch link information for all Bit.ly links at once
    my $bitly_info = {};
    my $bitly_ids = [ grep { defined $_ } values %{ $link_lookup } ];

    say STDERR "Fetching info for Bit.ly IDs " . join( ', ', @{ $bitly_ids } ) . "...";
    if ( scalar( @{ $bitly_ids } ) )
    {
        eval { $bitly_info = MediaWords::Util::Bitly::bitly_info_hashref( $bitly_ids ); };
        if ( $@ or ( !$bitly_info ) )
        {
            die "Unable to fetch Bit.ly info for Bit.ly IDs " . join( ', ', @{ $bitly_ids } ) . ": $@";
        }
    }

    say STDERR "Link info: " . Dumper( $bitly_info );

    my $link_stats = {};

    # Fetch Bit.ly stats for the link (if any)
    foreach my $link ( keys %{ $link_lookup } )
    {

        unless ( defined $link_lookup->{ $link } )
        {
            next;
        }

        unless ( defined $link_stats->{ 'data' } )
        {
            $link_stats->{ 'data' } = {};
        }

        my $bitly_id = $link_lookup->{ $link };

        say STDERR "Fetching stats for Bit.ly ID $bitly_id...";
        if ( $link_stats->{ 'data' }->{ $bitly_id } )
        {
            die "Bit.ly ID $bitly_id already exists in link stats hashref: " . Dumper( $link_stats );
        }

        $link_stats->{ 'data' }->{ $bitly_id } = {};

        if ( $BITLY_FETCH_CATEGORIES )
        {
            say STDERR "Fetching categories for Bit.ly ID $bitly_id...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'categories' } =
              MediaWords::Util::Bitly::bitly_link_categories( $bitly_id );
        }
        if ( $BITLY_FETCH_CLICKS )
        {
            say STDERR "Fetching clicks for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'clicks' } = [

                # array because one might want to make multiple requests with various dates
                MediaWords::Util::Bitly::bitly_link_clicks( $bitly_id, $start_timestamp, $end_timestamp )
            ];
        }
        if ( $BITLY_FETCH_REFERRERS )
        {
            say STDERR "Fetching referrers for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'referrers' } = [

                # array because one might want to make multiple requests with various dates
                MediaWords::Util::Bitly::bitly_link_referrers( $bitly_id, $start_timestamp, $end_timestamp )
            ];
        }
        if ( $BITLY_FETCH_SHARES )
        {
            say STDERR "Fetching shares for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'shares' } = [

                # array because one might want to make multiple requests with various dates
                MediaWords::Util::Bitly::bitly_link_shares( $bitly_id, $start_timestamp, $end_timestamp )
            ];
        }

    }

    # No links?
    if ( scalar( keys %{ $link_stats } ) )
    {

        # Collection timestamp (GMT, not local time)
        $link_stats->{ 'collection_timestamp' } = time();

    }
    else
    {

        # Mark as "not found"
        $link_stats->{ 'error' } = 'NOT_FOUND';
    }

    return $link_stats;
}

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id      = $args->{ stories_id }      or die "'stories_id' is not set.";
    my $start_timestamp = $args->{ start_timestamp } or die "'start_timestamp' is not set.";
    my $end_timestamp   = $args->{ end_timestamp }   or die "'end_timestamp' is not set.";

    my $stats = _fetch_story_stats( $db, $stories_id, $start_timestamp, $end_timestamp );
    unless ( ref( $stats ) eq ref( {} ) )
    {
        die "Stats for story ID $stories_id is not a hashref.";
    }

    say STDERR "Stats: " . Dumper( $stats );
}

# write a single log because there are a lot of CoreNLP processing jobs so it's
# impractical to log each job into a separate file
sub unify_logs()
{
    return 1;
}

# (Gearman::JobScheduler::AbstractFunction implementation) Return default configuration
sub configuration()
{
    return MediaWords::Util::GearmanJobSchedulerConfiguration->instance;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
