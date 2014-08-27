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
use MediaWords::KeyValueStore::GridFS;
use MediaWords::Util::Bitly;
use MediaWords::Util::JSON;
use MediaWords::Util::Process;
use Readonly;
use Data::Dumper;
use DateTime;
use Scalar::Defer;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

{
    # Object to determine what kind of stats to fetch from Bit.ly (used in
    # _fetch_story_stats())
    package MediaWords::Util::Bitly::StatsToFetch;

    sub new($;$$$$)
    {
        my $class = shift;
        my ( $fetch_categories, $fetch_clicks, $fetch_referrers, $fetch_shares ) = @_;

        my $self = {};
        bless $self, $class;

        # Default values
        $self->{ fetch_categories } = $fetch_categories // 0;
        $self->{ fetch_clicks }     = $fetch_clicks     // 1;
        $self->{ fetch_referrers }  = $fetch_referrers  // 1;
        $self->{ fetch_shares }     = $fetch_shares     // 0;

        return $self;
    }

    1;
}

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
    my $gridfs_database_name = $config->{ mongodb_gridfs }->{ bitly }->{ database_name };
    unless ( $gridfs_database_name )
    {
        fatal_error( "CoreNLP annotator is enabled, but MongoDB GridFS database name is not set." );
    }

    my $gridfs_store = MediaWords::KeyValueStore::GridFS->new( { database_name => $gridfs_database_name } );
    say STDERR "Will write CoreNLP annotator results to GridFS database: $gridfs_database_name";

    return $gridfs_store;
};

sub _fetch_story_stats($$$$;$)
{
    my ( $db, $stories_id, $start_timestamp, $end_timestamp, $stats_to_fetch ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    {
        $Data::Dumper::Indent = 0;

        if ( defined $stats_to_fetch )
        {

            unless ( ref( $stats_to_fetch ) eq 'MediaWords::Util::Bitly::StatsToFetch' )
            {
                die "'stats_to_fetch' must be an instance of MediaWords::Util::Bitly::StatsToFetch";
            }

            say STDERR "Will fetch the following Bit.ly stats: " . Dumper( $stats_to_fetch );

        }
        else
        {
            $stats_to_fetch = MediaWords::Util::Bitly::StatsToFetch->new();
            say STDERR "Will fetch default Bit.ly stats: " . Dumper( $stats_to_fetch );
        }

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

        if ( $stats_to_fetch->{ fetch_categories } )
        {
            say STDERR "Fetching categories for Bit.ly ID $bitly_id...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'categories' } =
              MediaWords::Util::Bitly::bitly_link_categories( $bitly_id );
        }
        if ( $stats_to_fetch->{ fetch_clicks } )
        {
            say STDERR "Fetching clicks for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'clicks' } = [

                # array because one might want to make multiple requests with various dates
                MediaWords::Util::Bitly::bitly_link_clicks( $bitly_id, $start_timestamp, $end_timestamp )
            ];
        }
        if ( $stats_to_fetch->{ fetch_referrers } )
        {
            say STDERR "Fetching referrers for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'referrers' } = [

                # array because one might want to make multiple requests with various dates
                MediaWords::Util::Bitly::bitly_link_referrers( $bitly_id, $start_timestamp, $end_timestamp )
            ];
        }
        if ( $stats_to_fetch->{ fetch_shares } )
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

sub _write_story_stats($$$;$)
{
    my ( $db, $stories_id, $stats, $overwrite ) = @_;

    unless ( $stories_id )
    {
        die "'stories_id' is not set.";
    }
    unless ( ref( $stats ) eq ref( {} ) )
    {
        die "Stats is not a hashref.";
    }

    # Check if something is already stored
    my $record_exists = undef;
    eval { $record_exists = $_gridfs_store->content_exists( $db, $stories_id ); };
    if ( $@ )
    {
        die "GridFS died while testing whether or not a Bit.ly record exists for story $stories_id: $@";
    }

    if ( $record_exists )
    {
        if ( $overwrite )
        {
            say STDERR "Bit.ly record for story $stories_id already exists in GridFS, will overwrite.";
        }
        else
        {
            die "Bit.ly record for story $stories_id already exists in GridFS.";
        }
    }

    # Convert results to a minimized JSON
    my $json_stats;
    eval { $json_stats = MediaWords::Util::JSON::encode_json( $stats ); };
    if ( $@ or ( !$json_stats ) )
    {
        die "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $stats );
    }

    say STDERR 'JSON length: ' . length( $json_stats );

    # Write to GridFS, index by stories_id
    eval {
        my $param_skip_encode_and_compress  = 0;    # Objects should be compressed
        my $param_use_bzip2_instead_of_gzip = 0;    # Gzip works better in Bit.ly's case

        my $path = $_gridfs_store->store_content(
            $db, $stories_id, \$json_stats,
            $param_skip_encode_and_compress,
            $param_use_bzip2_instead_of_gzip
        );
    };
    if ( $@ )
    {
        die "Unable to store Bit.ly result to GridFS: $@";
    }
}

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    Readonly my $BITLY_FETCH_CATEGORIES => 0;
    Readonly my $BITLY_FETCH_CLICKS     => 1;
    Readonly my $BITLY_FETCH_REFERRERS  => 1;
    Readonly my $BITLY_FETCH_SHARES     => 0;

    Readonly my $stats_to_fetch => MediaWords::Util::Bitly::StatsToFetch->new(
        $BITLY_FETCH_CATEGORIES,    # "/v3/link/category"
        $BITLY_FETCH_CLICKS,        # "/v3/link/clicks"
        $BITLY_FETCH_REFERRERS,     # "/v3/link/referrers"
        $BITLY_FETCH_SHARES         # "/v3/link/shares"
    );

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id      = $args->{ stories_id }      or die "'stories_id' is not set.";
    my $start_timestamp = $args->{ start_timestamp } or die "'start_timestamp' is not set.";
    my $end_timestamp   = $args->{ end_timestamp }   or die "'end_timestamp' is not set.";

    say STDERR "Fetching story stats for story $stories_id...";

    my $stats = _fetch_story_stats( $db, $stories_id, $start_timestamp, $end_timestamp, $stats_to_fetch );
    unless ( ref( $stats ) eq ref( {} ) )
    {
        die "Stats for story ID $stories_id is not a hashref.";
    }
    say STDERR "Done fetching story stats for story $stories_id.";

    # say STDERR "Stats: " . Dumper( $stats );

    say STDERR "Storing story stats for story $stories_id...";
    Readonly my $overwrite => 1;
    _write_story_stats( $db, $stories_id, $stats, $overwrite );
    say STDERR "Done storing story stats for story $stories_id.";
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
