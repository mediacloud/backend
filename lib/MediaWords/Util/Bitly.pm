package MediaWords::Util::Bitly;

#
# Bit.ly helper
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Bitly::API;
use MediaWords::Util::Bitly::StoryStats;
use MediaWords::Util::Process;
use MediaWords::Util::URL;
use MediaWords::Util::Config;
use MediaWords::Util::JSON;
use MediaWords::Util::Log;
use MediaWords::Util::SQL;
use JSON;
use List::MoreUtils qw( uniq );
use Scalar::Defer;
use Readonly;

# PostgreSQL table name for storing raw Bit.ly processing results
Readonly my $BITLY_POSTGRESQL_KVS_TABLE_NAME => 'bitly_processing_results';

# Whether to compress processing results using Bzip2 instead of Gzip
Readonly my $BITLY_USE_BZIP2 => 0;    # Gzip works better in Bit.ly's case

# (Lazy-initialized) Results store
#
# We use a static, package-wide variable here because:
# a) PostgreSQL handler should support being used by multiple threads by now, and
# b) each job worker is a separate process so there shouldn't be any resource clashes.
my $_results_store = lazy
{
    # this is (probably) an expensive module to load, so lazy load it
    require MediaWords::KeyValueStore::PostgreSQL;
    require MediaWords::KeyValueStore::AmazonS3;
    require MediaWords::KeyValueStore::CachedAmazonS3;
    require MediaWords::KeyValueStore::MultipleStores;

    my $config = MediaWords::Util::Config->get_config();

    unless ( bitly_processing_is_enabled() )
    {
        fatal_error( "Bit.ly processing is not enabled; why are you accessing this variable?" );
    }

    my $read_locations  = $config->{ bitly }->{ json_read_stores };
    my $write_locations = $config->{ bitly }->{ json_write_stores };

    unless ( defined $read_locations and defined $write_locations )
    {
        fatal_error( "Both 'read_locations' and 'write_locations' must be defined." );
    }
    unless ( ref( $read_locations ) eq ref( [] ) and ref( $write_locations ) eq ref( [] ) )
    {
        fatal_error( "Both 'read_locations' and 'write_locations' must be arrayrefs." );
    }
    unless ( scalar( @{ $read_locations } ) > 0 and scalar( @{ $write_locations } ) > 0 )
    {
        fatal_error( "Both 'read_locations' and 'write_locations' must contain at least one store." );
    }

    sub _store_from_location($)
    {
        my $location = shift;

        if ( $location eq 'postgresql' )
        {
            return MediaWords::KeyValueStore::PostgreSQL->new( { table => $BITLY_POSTGRESQL_KVS_TABLE_NAME } );

        }
        elsif ( $location eq 'amazon_s3' )
        {
            my $config = MediaWords::Util::Config->get_config();

            unless ( $config->{ amazon_s3 }->{ bitly_processing_results }->{ access_key_id } )
            {
                die "Bit.ly is configured to read / write to S3, but S3 credentials for Bit.ly are not configured.";
            }

            my $store_package_name = 'MediaWords::KeyValueStore::AmazonS3';
            my $cache_root_dir     = undef;
            if ( $config->{ amazon_s3 }->{ bitly_processing_results }->{ cache_root_dir } )
            {
                $store_package_name = 'MediaWords::KeyValueStore::CachedAmazonS3';
                $cache_root_dir     = $config->{ mediawords }->{ data_dir } .
                  '/cache/' . $config->{ amazon_s3 }->{ bitly_processing_results }->{ cache_root_dir };
            }

            return $store_package_name->new(
                {
                    access_key_id     => $config->{ amazon_s3 }->{ bitly_processing_results }->{ access_key_id },
                    secret_access_key => $config->{ amazon_s3 }->{ bitly_processing_results }->{ secret_access_key },
                    bucket_name       => $config->{ amazon_s3 }->{ bitly_processing_results }->{ bucket_name },
                    directory_name    => $config->{ amazon_s3 }->{ bitly_processing_results }->{ directory_name },
                    cache_root_dir    => $cache_root_dir,
                }
            );

        }
        else
        {
            die "Unknown store location: $location";
        }
    }

    my @read_stores;
    my @write_stores;
    eval {
        foreach my $location ( @{ $read_locations } )
        {
            push( @read_stores, _store_from_location( $location ) );
        }
        foreach my $location ( @{ $write_locations } )
        {
            push( @write_stores, _store_from_location( $location ) );
        }
    };
    if ( $@ )
    {
        fatal_error( "Unable to initialize store for Bit.ly raw results reading / writing: $@" );
    }

    return MediaWords::KeyValueStore::MultipleStores->new(
        {
            stores_for_reading => \@read_stores,     #
            stores_for_writing => \@write_stores,    #
        }
    );
};

# Returns true if Bit.ly processing is enabled
sub bitly_processing_is_enabled()
{
    my $config = MediaWords::Util::Config->get_config();
    my $bitly_enabled = $config->{ bitly }->{ enabled } // '';

    return ( $bitly_enabled eq 'yes' );
}

# Check if story is processed with Bit.ly (stats are fetched)
# Return 1 if stats for story are fetched, 0 otherwise, die() on error, exit() on fatal error
sub story_stats_are_fetched($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $record_exists = undef;
    eval { $record_exists = ( force $_results_store)->content_exists( $db, $stories_id ); };
    if ( $@ )
    {
        die "Storage died while testing whether or not a Bit.ly record exists for story $stories_id: $@";
    }

    return $record_exists;
}

# Fetch story URL statistics from Bit.ly API
#
# Params:
# * $db - database object
# * $stories_id - story ID
# * $start_timestamp - starting date (offset) for fetching statistics
# * $end_timestamp - ending date (limit) for fetching statistics
#
# Returns: see fetch_stats_for_url()
#
# die()s on error
sub fetch_stats_for_story($$$$)
{
    my ( $db, $stories_id, $start_timestamp, $end_timestamp ) = @_;

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Story ID $stories_id was not found.";
    }

    my $stories_url = $story->{ url };

    unless ( $stories_url )
    {
        die "URL is unset for story $stories_id";
    }
    unless ( MediaWords::Util::URL::is_http_url( $stories_url ) )
    {
        die "URL '$stories_url' is not a HTTP(S) URL for story $stories_id";
    }

    return MediaWords::Util::Bitly::API::fetch_stats_for_url( $db, $stories_url, $start_timestamp, $end_timestamp );
}

# Merge two Bit.ly statistics hashrefs into one
sub merge_story_stats($$)
{
    my ( $old_stats, $new_stats ) = @_;

    if ( $old_stats->{ 'error' } )
    {
        DEBUG( sub { "Fetching old stats failed, overwriting with new stats" } );
        return $new_stats;
    }

    if ( $new_stats->{ 'error' } )
    {
        DEBUG( sub { "Fetching new stats failed, overwriting with old stats" } );
        return $old_stats;
    }

    my @all_bitly_ids;
    push( @all_bitly_ids, keys %{ $old_stats->{ 'data' } } );
    push( @all_bitly_ids, keys %{ $new_stats->{ 'data' } } );
    @all_bitly_ids = uniq( @all_bitly_ids );

    # Merge in old stats into new ones
    my $stats = { data => {} };
    foreach my $bitly_id ( @all_bitly_ids )
    {
        my $old_bitly_data = $old_stats->{ data }->{ $bitly_id };
        my $new_bitly_data = $new_stats->{ data }->{ $bitly_id };

        if ( ( !$old_bitly_data ) or dump_terse( $old_bitly_data ) eq dump_terse( $new_bitly_data ) )
        {
            DEBUG( sub { "Stats for Bit.ly hash $bitly_id are identical or old stats didn't exist, using new stats" } );
            $stats->{ data }->{ $bitly_id } = $new_bitly_data;
        }
        else
        {
            $stats->{ data }->{ $bitly_id } = $old_bitly_data;
            DEBUG( sub { "Both new and old stats have click data for Bit.ly hash $bitly_id, merging stats" } );
            foreach my $bitly_clicks ( @{ $new_bitly_data->{ clicks } } )
            {
                push( @{ $stats->{ data }->{ $bitly_id }->{ clicks } }, $bitly_clicks );
            }

            # Update collection timestamp
            $stats->{ collection_timestamp } = $new_stats->{ collection_timestamp };
        }
    }

    return $stats;
}

# Write Bit.ly story statistics to key-value store; append to the existing
# stats if needed
#
# Params:
# * $db - database object
# * $stories_id - story ID
# * $stats - hashref with Bit.ly statistics
#
# die()s on error
sub write_story_stats($$$)
{
    my ( $db, $stories_id, $stats ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    unless ( $stories_id )
    {
        die "'stories_id' is not set.";
    }
    unless ( ref( $stats ) eq ref( {} ) )
    {
        die "Stats is not a hashref.";
    }

    # Fetch + merge existing stats if any
    if ( story_stats_are_fetched( $db, $stories_id ) )
    {
        DEBUG( sub { "Story's $stories_id stats are already fetched from Bit.ly, merging..." } );

        my $existing_stats = read_story_stats( $db, $stories_id );
        $stats = merge_story_stats( $existing_stats, $stats );
    }

    # Convert results to a minimized JSON
    my $json_stats;
    eval { $json_stats = MediaWords::Util::JSON::encode_json( $stats ); };
    if ( $@ or ( !$json_stats ) )
    {
        die "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $stats );
    }

    DEBUG( sub { 'JSON length: ' . length( $json_stats ) } );

    # Write to key-value store, index by stories_id
    eval {
        my $param_use_bzip2_instead_of_gzip = $BITLY_USE_BZIP2;

        my $path =
          ( force $_results_store)->store_content( $db, $stories_id, \$json_stats, $param_use_bzip2_instead_of_gzip );
    };
    if ( $@ )
    {
        die "Unable to store Bit.ly result to store: $@";
    }
}

# Read Bit.ly story statistics from key-value store
#
# Params:
# * $db - database object
# * $stories_id - story ID
#
# Returns hashref with decoded JSON, undef if story is not processed; die()s on error
sub read_story_stats($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    unless ( $stories_id )
    {
        die "'stories_id' is not set.";
    }

    # Check if something is already stored
    unless ( story_stats_are_fetched( $db, $stories_id ) )
    {
        warn "Story $stories_id is not processed with Bit.ly.";
        return undef;
    }

    # Fetch processing result
    my $json_ref = undef;

    my $param_object_path                   = undef;
    my $param_use_bunzip2_instead_of_gunzip = $BITLY_USE_BZIP2;

    eval {
        $json_ref = ( force $_results_store)
          ->fetch_content( $db, $stories_id, $param_object_path, $param_use_bunzip2_instead_of_gunzip );
    };
    if ( $@ or ( !defined $json_ref ) )
    {
        die "Storage died while fetching Bit.ly stats for story $stories_id: $@\n";
    }

    my $json = $$json_ref;
    unless ( $json )
    {
        die "Fetched stats are undefined or empty for story $stories_id.\n";
    }

    my $json_hashref;
    eval { $json_hashref = MediaWords::Util::JSON::decode_json( $json ); };
    if ( $@ or ( !ref $json_hashref ) )
    {
        die "Unable to parse Bit.ly stats JSON for story $stories_id: $@\nString JSON: $json";
    }

    return $json_hashref;
}

# Return the number of controversy's stories that don't yet have aggregated Bit.ly statistics
sub num_controversy_stories_without_bitly_statistics($$)
{
    my ( $db, $controversies_id ) = @_;

    my ( $num_controversy_stories_without_bitly_statistics ) = $db->query( <<SQL, $controversies_id )->flat;
select count(*)
    from controversy_stories cs
        left join bitly_clicks_total b on ( cs.stories_id = b.stories_id )
    where cs.controversies_id = ?

      -- Don't touch "click_count" column so that the match could be made using
      -- the index only.
      --
      -- "click_count" is NOT NULL so if story doesn't have a click count
      -- collected yet, the row will be nonexistent (thus testing just the
      -- "stories_id" works too).
      and b.stories_id is null
SQL

    unless ( defined $num_controversy_stories_without_bitly_statistics )
    {
        die "'num_controversy_stories_without_bitly_statistics' is undefined.";
    }

    return $num_controversy_stories_without_bitly_statistics;
}

# Returns MediaWords::Util::Bitly::StoryStats object with story statistics
# die()s on error
sub aggregate_story_stats($$$)
{
    my ( $stories_id, $stories_original_url, $stats ) = @_;

    my $click_count = 0;

    my $dates_and_clicks = {};

    # Aggregate stats
    if ( $stats->{ 'error' } )
    {
        if ( $stats->{ 'error' } eq 'NOT_FOUND' )
        {
            DEBUG( sub { "Story $stories_id was not found on Bit.ly, so click count is 0." } );
        }
        else
        {
            die "Story $stories_id has encountered unknown error while collecting Bit.ly stats: " . $stats->{ 'error' };
        }
    }
    else
    {
        my $stories_original_url_is_homepage = MediaWords::Util::URL::is_homepage_url( $stories_original_url );

        unless ( $stats->{ 'data' } )
        {
            die "'data' is not set for story's $stories_id stats hashref.";
        }

        foreach my $bitly_id ( keys %{ $stats->{ 'data' } } )
        {
            my $bitly_data = $stats->{ 'data' }->{ $bitly_id };

            # If URL gets redirected to the homepage (e.g.
            # http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/ leads
            # to http://www.wired.com/), don't use those redirects
            my $url = $bitly_data->{ 'url' };
            unless ( $stories_original_url_is_homepage )
            {
                if ( MediaWords::Util::URL::is_homepage_url( $url ) )
                {
                    DEBUG( sub { "URL $stories_original_url redirected to $url; looks like homepage; skipping." } );
                    next;
                }
            }

            # Click count (indiscriminate from date range)
            unless ( $bitly_data->{ 'clicks' } )
            {
                DEBUG( sub { "Bit.ly stats doesn't have 'clicks' key for Bit.ly ID $bitly_id, story $stories_id." } );
            }

            my $hash_dates_and_clicks = {};

            foreach my $bitly_clicks ( @{ $bitly_data->{ 'clicks' } } )
            {
                my $temp_dates_and_clicks = {};

                foreach my $link_clicks ( @{ $bitly_clicks->{ 'link_clicks' } } )
                {
                    my $date   = MediaWords::Util::SQL::get_sql_date_from_epoch( $link_clicks->{ 'dt' } + 0 );
                    my $clicks = $link_clicks->{ 'clicks' };

                    $hash_dates_and_clicks->{ $date } = $clicks;
                }
            }

            # "clicks" array might have multiple child dictionaries, this
            # means that click data was fetched multiple times (e.g. at
            # day 3 and day 30 after publish_date). Data is ordered in
            # ascending order, i.e. newer data is at the end of the array.
            # Days for which stats were fetched might not necessarily be
            # identical (they might overlap or not). In that case, use the
            # newest stats for individual days where available but don't
            # overwrite stats for old days that aren't available in the
            # newer stats.
            foreach my $date ( keys %{ $hash_dates_and_clicks } )
            {
                $dates_and_clicks->{ $date } //= 0;
                $dates_and_clicks->{ $date } += $hash_dates_and_clicks->{ $date };
            }
        }
    }

    return MediaWords::Util::Bitly::StoryStats->new( $stories_id, $dates_and_clicks );
}

1;
