package MediaWords::Solr::Dump;

=head1 NAME

MediaWords::Solr::Dump - import story_sentences from postgres into solr

=head1 SYNOPSIS

    # import updates stories into solr
    import_data( $db );

    # regenerate entire solr database
    queue_all_stories( $db );
    delete_all_stories( $db );
    import_data( $db, { full => 1 } );


=head1 DESCRIPTION

This module implements the functionality to import data from postgres into solr.

The module knows which sentences to import by keep track of db_row_last_updated fields on the stories, media, and
story_sentences table.  The module queries story_sentences for all distinct stories for which the db_row_last_updated
value is greater than the latest value in solr_imports.  Triggers in the postgres database update the
story_sentences.db_row_last_updated value on story_sentences whenever a related story, medium, story tag, story sentence
tag, or story sentence tag is updated.

In addition to the incremental imports by db_row_last_updated, we import any stories in solr_import_extra_stories,
in chunks up to 100k until the solr_import_extra_stories queue has been cleared.  In addition to using the queue to
manually trigger updates for specific stories, we use it to queue updates for entire media sources whose tags have been
changed and to queue updates for stories whose bitly data have been updated.

This module has been carefully tuned to optimize performance.  Make sure you test the performance impacts of any
changes you make to the module.

=back

=cut

#use forks;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

require Cpanel::JSON::XS;
use Data::Dumper;
use Digest::MD5;
use Encode;
use FileHandle;
use JSON::PP;
use List::MoreUtils;
use List::Util;
use Parallel::ForkManager;
use Readonly;
use URI;

require bytes;    # do not override length() and such

use MediaWords::DB;
use MediaWords::Util::Config;
use MediaWords::Util::Paths;
use MediaWords::Util::Web;
use MediaWords::Solr;
use MediaWords::Test::DB;

# order and names of fields exported to and imported from csv
Readonly my @SOLR_FIELDS => qw/stories_id media_id publish_date publish_day publish_week publish_month publish_year
  text title language processed_stories_id tags_id_stories timespans_id/;

# how many sentences to fetch at a time from the postgres query
Readonly my $FETCH_BLOCK_SIZE => 100;

# default stories queue table
Readonly my $DEFAULT_STORIES_QUEUE_TABLE => 'solr_import_extra_stories';

# mark date before generating dump for storing in solr_imports after successful import
my $_import_date;

# options
my $_solr_use_staging;
my $_stories_queue_table;

# keep track of the max stories_id from the last time we queried the queue table so that we don't have to
# page through a ton of dead rows when importing a big queue table
my $_last_max_queue_stories_id;

=head2 FUNCTIONS

=cut

# return the $_stories_queue_table, which is set by the queue_table option of import_data()
sub _get_stories_queue_table
{
    return $_stories_queue_table;
}

# add enough stories from the stories queue table to the delta_import_stories table that there are up to
# _get_maxed_queued_stories in delta_import_stories for each solr_import
sub _add_extra_stories_to_import
{
    my ( $db, $import_date, $num_delta_stories, $queue_only ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    my $max_queued_stories = $config->{ mediawords }->{ solr_import }->{ max_queued_stories };

    my $stories_queue_table = _get_stories_queue_table();

    # first import any stories from snapshotted topics so that those snapshots become searchable ASAP.
    # do this as a separate query because I couldn't figure out a single query that resulted in a reasonable
    # postgres query plan given a very large stories queue table
    my $num_queued_stories = 0;
    if ( !$queue_only )
    {
        my $num_queued_stories = $db->query(
            <<"SQL",
            INSERT INTO delta_import_stories (stories_id)
                SELECT sies.stories_id
                FROM $stories_queue_table sies
                    join snap.stories ss using ( stories_id )
                    join snapshots s on ( ss.snapshots_id = s.snapshots_id and not s.searchable )
                ORDER BY sies.stories_id
                LIMIT ?
SQL
            $max_queued_stories
        )->rows;
    }

    INFO "added $num_queued_stories topic stories to the import";

    $max_queued_stories -= $num_queued_stories;

    # keep track of last max queued id so that we can search for only stories greater than that id below.  otherwise,
    # the index scan from the query has to fetch all of the previously deleted rows from the heap and turn an instant
    # query into a 10 second query after a couple million story imports
    my $min_stories_id = 0;
    if ( $queue_only && $_last_max_queue_stories_id )
    {
        $min_stories_id = $_last_max_queue_stories_id;
    }

    # order by stories_id so that we will tend to get story_sentences in chunked pages as much as possible; just using
    # random stories_ids for collections of old stories (for instance queued to the stories queue table from a
    # media tag update) can make this query a couple orders of magnitude slower
    $num_queued_stories += $db->query(
        <<"SQL",
        INSERT INTO delta_import_stories (stories_id)
            SELECT stories_id
            FROM $stories_queue_table s
            WHERE stories_id > ?
            ORDER BY stories_id
            LIMIT ?
SQL
        $min_stories_id,
        $max_queued_stories
    )->rows;

    if ( $num_queued_stories > 0 )
    {
        my $stories_queue_table = _get_stories_queue_table();

        # remove the schema if present
        my $relname = _get_stories_queue_table();
        $relname =~ s/.*\.//;

        # use pg_class estimate to avoid expensive count(*) query
        my ( $total_queued_stories ) = $db->query( <<SQL, $relname )->flat;
select reltuples::bigint from pg_class where relname = ?
SQL

        ( $_last_max_queue_stories_id ) = $db->query( "select max( stories_id ) from delta_import_stories" )->flat();

        INFO "added $num_queued_stories out of about $total_queued_stories queued stories to the import";
    }

}

# query for stories to import, including concatenated sentences as story text and metadata joined in from other tables.
# return a hash in the form { json => $json_of_stories, stories_ids => $list_of_stories_ids }
sub _get_stories_json_from_db_single
{
    my ( $db, $stories_ids ) = @_;

    # query in blocks of $FETCH_BLOCK_SIZE stories to encourage postgres to generate sane query plans.

    my $all_stories = [];

    my $fetch_stories_ids = [ @{ $stories_ids } ];

    INFO( "fetching stories from postgres (" . scalar( @{ $fetch_stories_ids } ) . " remaining)" );

    while ( @{ $fetch_stories_ids } )
    {
        my $block_stories_ids = [];
        for my $i ( 1 .. $FETCH_BLOCK_SIZE )
        {
            if ( my $stories_id = pop( @{ $fetch_stories_ids } ) )
            {
                push( @{ $block_stories_ids }, $stories_id );
            }
        }

        my $block_stories_ids_list = join( ',', @{ $block_stories_ids } );

        TRACE( "fetching stories ids: $block_stories_ids_list" );
        $db->query( "SET LOCAL client_min_messages=warning" );

        my $stories = $db->query( <<SQL )->hashes();
with _block_processed_stories as (
    select processed_stories_id, stories_id
        from processed_stories
        where stories_id in ( $block_stories_ids_list )
),

_timespan_stories as  (
    select  stories_id, array_agg( distinct timespans_id ) timespans_id
        from snap.story_link_counts slc
            join _block_processed_stories using ( stories_id )
        where
            slc.stories_id in ( $block_stories_ids_list )
        group by stories_id
),

_tag_stories as  (
    select stories_id, array_agg( distinct tags_id ) tags_id_stories
        from stories_tags_map stm
            join _block_processed_stories bps using ( stories_id )
        where
            stm.stories_id in ( $block_stories_ids_list )
        group by stories_id
),

_import_stories as (
    select
        s.stories_id,
        s.media_id,
        to_char( date_trunc( 'minute', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date,
        to_char( date_trunc( 'day', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_day,
        to_char( date_trunc( 'week', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_week,
        to_char( date_trunc( 'month', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_month,
        to_char( date_trunc( 'year', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_year,
        string_agg( ss.sentence, ' ' order by ss.sentence_number ) as text,
        s.title,
        s.language,
        max( ps.processed_stories_id ) processed_stories_id,
        min( stm.tags_id_stories ) tags_id_stories,
        min( slc.timespans_id ) timespans_id

    from _block_processed_stories ps
        join story_sentences ss using ( stories_id )
        join stories s using ( stories_id )
        left join _tag_stories stm using ( stories_id )
        left join _timespan_stories slc using ( stories_id )

    where
        s.stories_id in ( $block_stories_ids_list )
    group by s.stories_id
)


select * from _import_stories
SQL

        TRACE( "found " . scalar( @{ $stories } ) . " stories from " . scalar( @{ $block_stories_ids } ) . " ids" );

        push( @{ $all_stories }, @{ $stories } );
    }

    my $all_stories_ids = [ map { $_->{ stories_id } } @{ $all_stories } ];
    my $stories_json = Cpanel::JSON::XS::encode_json( $all_stories );

    #DEBUG( $stories_json );

    return { stories_ids => $all_stories_ids, json => $stories_json };
}

# get stories_json for import from db and import the resulting stories into solr.  return the list of stories_ids
# imported.
sub _import_stories_from_db_single($$)
{
    my ( $db, $stories_ids ) = @_;

    # if this is called as a threaded function, $db will be undef so that it can be recreated
    $db //= MediaWords::DB::connect_to_db();

    my $json = _get_stories_json_from_db_single( $db, $stories_ids );

    my ( $import_url, $import_params ) = _get_import_url_params();

    DEBUG "importing " . scalar( @{ $json->{ stories_ids } } ) . " stories into solr ...";
    eval { _solr_request( $db, $import_url, $import_params, $json->{ json }, 'application/json' ); };
    die( "error importing to solr: $@" ) if ( $@ );

    TRACE( "committing solr index changes ..." );
    _solr_request( $db, 'update', { 'commit' => 'true' } );

    _delete_stories_from_import_queue( $db, $stories_ids );

    return $json->{ stories_ids };
}

# this function does the meat of the work of querying story data from postgres and importing that data to solr
sub _import_stories($$)
{
    my ( $db, $jobs ) = @_;

    my $stories_ids = $db->query( "select distinct stories_id from delta_import_stories" )->flat;

    if ( $jobs == 1 )
    {
        _import_stories_from_db_single( $db, $stories_ids );
        return;
    }

    my $pm = Parallel::ForkManager->new( $jobs );

    my $stories_per_job = int( scalar( @{ $stories_ids } ) / $jobs ) + 1;
    my $iter = List::MoreUtils::natatime( $stories_per_job, @{ $stories_ids } );
    while ( my @job_stories_ids = $iter->() )
    {
        $pm->start() && next;
        _import_stories_from_db_single( undef, \@job_stories_ids );
        $pm->finish();
    }

    $pm->wait_all_children();

    return;
}

# limit delta_import_stories to max_queued_stories stories;  put excess stories in solr_extra_import_stories
sub _restrict_delta_import_stories_size ($$)
{
    my ( $db, $num_delta_stories ) = @_;

    my $max_queued_stories = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_import }->{ max_queued_stories };

    return if ( $num_delta_stories <= $max_queued_stories );

    DEBUG( "cutting delta import stories from $num_delta_stories to $max_queued_stories stories" );

    my $stories_queue_table = _get_stories_queue_table();

    $db->query( <<SQL, $max_queued_stories );
create temporary table keep_ids as
    select * from delta_import_stories order by stories_id limit ?
SQL

    $db->query( "delete from delta_import_stories where stories_id in ( select stories_id from keep_ids )" );

    $db->query( "insert into $stories_queue_table ( stories_id ) select stories_id from delta_import_stories" );

    $db->query( "drop table delta_import_stories" );

    $db->query( "alter table keep_ids rename to delta_import_stories" );

}

# get the delta clause that restricts the import of all subsequent queries to just the delta stories.  uses
# a temporary table called delta_import_stories to list which stories should be imported.  we do this instead
# of trying to query the date direclty because we need to restrict by this list in stand alone queries to various
# manually joined tables, like stories_tags_map.
sub _create_delta_import_stories($$)
{
    my ( $db, $queue_only ) = @_;

    my ( $import_date ) = $db->query( "select import_date from solr_imports order by import_date desc limit 1" )->flat;

    $db->query( "drop table if exists delta_import_stories" );

    my $num_delta_stories = 0;
    if ( $queue_only )
    {
        $db->query( "create temporary table delta_import_stories ( stories_id int )" );
    }
    else
    {
        $import_date //= '2000-01-01';

        INFO "importing delta from $import_date...";

        $db->query( <<SQL, $import_date );
create temporary table delta_import_stories as
    select distinct stories_id
        from story_sentences ss
            where ss.db_row_last_updated > \$1
SQL
        ( $num_delta_stories ) = $db->query( "select count(*) from delta_import_stories" )->flat;
        INFO "found $num_delta_stories stories for import ...";

        _restrict_delta_import_stories_size( $db, $num_delta_stories );
    }

    _add_extra_stories_to_import( $db, $import_date, $num_delta_stories, $queue_only );

    my $delta_stories_ids = $db->query( "select stories_id from delta_import_stories" )->flat;

    return $delta_stories_ids;
}

# Send a request to MediaWords::Solr::get_solr_url. Return content on success, die() on error. If $staging is true, use
# the staging collection; otherwise use the live collection.
sub _solr_request($$$;$$)
{
    my ( $db, $path, $params, $content, $content_type ) = @_;

    my $solr_url = MediaWords::Solr::get_solr_url;
    $params //= {};

    my $collection =
      $_solr_use_staging ? MediaWords::Solr::get_staging_collection( $db ) : MediaWords::Solr::get_live_collection( $db );

    my $abs_uri = URI->new( "$solr_url/$collection/$path" );
    $abs_uri->query_form( $params );
    my $abs_url = $abs_uri->as_string;

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_max_size( undef );

    # should be able to process about this fast.  otherwise, time out and throw error so that we can continue processing
    my $req;

    my $timeout = 600;

    # Remediate CVE-2017-12629
    if ( $params->{ q } )
    {
        if ( $params->{ q } =~ /xmlparser/i )
        {
            LOGCONFESS "XML queries are not supported.";
        }
    }

    TRACE "Requesting URL: $abs_url...";

    if ( $content )
    {
        $content_type ||= 'text/plain; charset=utf-8';

        $req = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $abs_url );
        $req->set_header( 'Content-Type',   $content_type );
        $req->set_header( 'Content-Length', bytes::length( $content ) );
        $req->set_content( $content );
    }
    else
    {
        $req = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $abs_url );
    }

    my $res;
    eval {
        local $SIG{ ALRM } = sub { die "alarm" };

        alarm $timeout;

        $ua->set_timeout( $timeout );
        $res = $ua->request( $req );

        alarm 0;
    };

    if ( $@ )
    {
        my $error_message = $@;

        if ( $error_message =~ /^alarm at/ )
        {
            die "Request to $abs_url timed out after $timeout seconds";
        }
        else
        {
            die "Request to $abs_url failed: $error_message";
        }
    }

    my $response = $res->decoded_content;
    unless ( $res->is_success )
    {
        die "Request to $abs_url returned HTTP error: $response";
    }

    return $response;
}

# get the solr url and parameters to send csv data to
sub _get_import_url_params
{
    my $url_params = {
        'commit'    => 'false',
        'overwrite' => 'false',
    };

    return ( 'update', $url_params );
}

# store in memory the current date according to postgres
sub _mark_import_date
{
    my ( $db ) = @_;

    ( $_import_date ) = $db->query( "select now()" )->flat;
}

# store the date marked by mark_import_date in solr_imports
sub _save_import_date
{
    my ( $db, $delta, $stories_ids ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    my $full_import = $delta ? 'f' : 't';
    $db->query( <<SQL, $_import_date, $full_import, scalar( @{ $stories_ids } ) );
insert into solr_imports( import_date, full_import, num_stories ) values ( ?, ?, ? )
SQL

}

# save log of all stories imported into solr
sub _save_import_log
{
    my ( $db, $stories_ids ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    $db->begin;
    for my $stories_id ( @{ $stories_ids } )
    {
        $db->query( <<SQL, $stories_id, $_import_date );
insert into solr_imported_stories ( stories_id, import_date ) values ( ?, ? )
SQL
    }
    $db->commit;
}

# given a list of stories_ids, return a stories_id:... solr query that replaces individual ids with ranges where
# possible.  Avoids >1MB queries that consists of lists of >100k stories_ids.
sub _get_stories_id_solr_query
{
    my ( $ids ) = @_;

    die( "empty stories_ids" ) unless ( @{ $ids } );

    $ids = [ sort { $a <=> $b } @{ $ids } ];

    my $singletons = [ -2 ];
    my $ranges = [ [ -2 ] ];
    for my $id ( @{ $ids } )
    {
        if ( $id == ( $ranges->[ -1 ]->[ -1 ] + 1 ) )
        {
            push( @{ $ranges->[ -1 ] }, $id );
        }
        elsif ( $id == ( $singletons->[ -1 ] + 1 ) )
        {
            push( @{ $ranges }, [ pop( @{ $singletons } ), $id ] );
        }
        else
        {
            push( @{ $singletons }, $id );
        }
    }

    shift( @{ $singletons } );
    shift( @{ $ranges } );

    my $long_ranges = [];
    for my $range ( @{ $ranges } )
    {
        if ( scalar( @{ $range } ) > 2 )
        {
            push( @{ $long_ranges }, $range );
        }
        else
        {
            push( @{ $singletons }, @{ $range } );
        }
    }

    my $queries = [];

    push( @{ $queries }, map { "stories_id:[$_->[ 0 ] TO $_->[ -1 ]]" } @{ $long_ranges } );
    push( @{ $queries }, 'stories_id:(' . join( ' ', @{ $singletons } ) . ')' ) if ( @{ $singletons } );

    my $query = join( ' ', @{ $queries } );

    return $query;
}

# delete the stories in the stories queue table
sub _delete_queued_stories($)
{
    my ( $db ) = @_;

    my $stories_queue_table = _get_stories_queue_table();

    my $stories_ids = $db->query( "select stories_id from $stories_queue_table" )->flat;

    return 1 unless ( $stories_ids && scalar @{ $stories_ids } );

    $stories_ids = [ sort { $a <=> $b } @{ $stories_ids } ];

    my $max_chunk_size = 5000;

    while ( @{ $stories_ids } )
    {
        my $chunk_ids = [];
        my $chunk_size = List::Util::min( $max_chunk_size, scalar( @{ $stories_ids } ) );
        map { push( @{ $chunk_ids }, shift( @{ $stories_ids } ) ) } ( 1 .. $chunk_size );

        INFO "deleting chunk: " . scalar( @{ $chunk_ids } ) . " stories ...";

        my $stories_id_query = _get_stories_id_solr_query( $chunk_ids );

        my $delete_query = "<delete><query>$stories_id_query</query></delete>";

        eval { _solr_request( $db, 'update', undef, $delete_query, 'application/xml' ); };
        if ( $@ )
        {
            my $error = $@;
            WARN "Error while deleting stories: $error";
            return 0;
        }
    }

    return 1;
}

# delete stories that have just been imported from the media import queue
sub _delete_stories_from_import_queue
{
    my ( $db, $stories_ids ) = @_;

    TRACE( "deleting " . scalar( @{ $stories_ids } ) . " stories from import queue ..." );

    my $stories_queue_table = _get_stories_queue_table();

    return unless ( @{ $stories_ids } );

    my $stories_ids_list = join( ',', @{ $stories_ids } );

    $db->query(
        <<SQL
        DELETE FROM $stories_queue_table
        WHERE stories_id IN ($stories_ids_list)
SQL
    );
}

# guess whether this might be a production solr instance by just looking at the size.  this is useful so that we can
# cowardly refuse to delete all content from something that may be a production instance.
sub _maybe_production_solr
{
    my ( $db ) = @_;

    my $num_sentences = MediaWords::Solr::get_num_found( $db, { q => '*:*', rows => 0 } );

    die( "Unable to query solr for number of sentences" ) unless ( defined( $num_sentences ) );

    return ( $num_sentences > 100_000_000 );
}

# return true if there are less than 100k rows in the stories queue table
sub _stories_queue_is_small
{
    my ( $db ) = @_;

    my $stories_queue_table = _get_stories_queue_table();

    my $exist = $db->query( "select 1 from $stories_queue_table offset 100000 limit 1" )->hash;

    return $exist ? 0 : 1;
}

# set snapshots.searchable to true for all snapshots that are currently false and
# have no stories in the stories queue table
sub _update_snapshot_solr_status
{
    my ( $db ) = @_;

    my $stories_queue_table = _get_stories_queue_table();

    # the combination the searchable clause and the not exists which stops after the first hit should
    # make this quite fast
    $db->query( <<SQL );
update snapshots s set searchable = true
    where
        searchable = false and
        not exists (
            select 1
                from timespans t
                    join snap.story_link_counts slc using ( timespans_id )
                    join $stories_queue_table sies using ( stories_id )
                where t.snapshots_id = s.snapshots_id
        )
SQL
}

# die if we are running on the testing databse but using the default solr index
sub _validate_using_test_db_with_test_index()
{
    my ( $db ) = @_;

    if ( MediaWords::Test::DB::using_test_database() && !MediaWords::Test::Solr::using_test_index() )
    {
        die( 'you are using a test database but not a test index.  call MediaWords::Test::Solr::setup_test_index()' );
    }
}

=head2 import_data( $options )

Import stories from postgres to solr.

Options:
* queue_only -- only import stories from the stories queue table, ignoring db_row_last_updated (default false)
* update -- delete each story from solr before importing it (default true)
* empty_queue -- keep running until stories queue table is entirely empty (default false)
* jobs -- number of parallel import jobs to run (default 1)
* throttle -- sleep this number of seconds between each block of stories (default 60)
* full -- shortcut for: queue_only=true, update=false, empty_queue=true, throttle=1
* stories_queue_table -- table from which to pull stories to import (default solr_import_extra_stories)
* skip_logging -- skip logging the import into the solr_import_stories or solr_imports tables (default=false)

The import will run in blocks of config.mediawords.solr_import.max_queued_stories at a time.  It will always process
one block, but by default it will exit once there are less than 100k stories left in the queue (to avoid endlessly
running on very small queues).

If jobs is > 1, the database handle passed into this function will be corrupted and must not be used after calling
this function.
=cut

sub import_data($;$)
{
    my ( $db, $options ) = @_;

    $options //= {};

    my $queue_only          = $options->{ queue_only }          // 0;
    my $update              = $options->{ update }              // 1;
    my $empty_queue         = $options->{ empty_queue }         // 0;
    my $jobs                = $options->{ jobs }                // 1;
    my $throttle            = $options->{ throttle }            // 60;
    my $staging             = $options->{ staging }             // 0;
    my $full                = $options->{ full }                // 0;
    my $stories_queue_table = $options->{ stories_queue_table } // $DEFAULT_STORIES_QUEUE_TABLE;
    my $skip_logging        = $options->{ skip_logging }        // 0;

    if ( $full )
    {
        $queue_only  = 1;
        $update      = 0;
        $empty_queue = 1;
        $throttle    = 1;
    }

    if ( $stories_queue_table ne $DEFAULT_STORIES_QUEUE_TABLE )
    {
        $skip_logging = 1;
        $empty_queue  = 1;
        $update       = 0;
        $queue_only   = 1;
    }

    $_solr_use_staging          = $staging;
    $_stories_queue_table       = $stories_queue_table;
    $_last_max_queue_stories_id = 0;

    my $i = 0;

    while ()
    {
        my $start_time = time();
        _mark_import_date( $db );

        my $stories_ids = _create_delta_import_stories( $db, $queue_only );

        last unless ( @{ $stories_ids } );

        if ( $update )
        {
            INFO "deleting updated stories ...";
            _delete_queued_stories( $db ) || die( "delete stories failed." );
        }

        _import_stories( $db, $jobs );

        # have to reconnect becaue import_stories may have forked, ruining existing db handles
        $db = MediaWords::DB::connect_to_db if ( $jobs > 1 );

        if ( !$skip_logging )
        {
            _save_import_date( $db, !$full, $stories_ids );
            _save_import_log( $db, $stories_ids );
        }

        if ( !$skip_logging )
        {
            _update_snapshot_solr_status( $db );
        }

        my $num_stories = scalar( @{ $stories_ids } );
        my $import_time = time() - $start_time;
        INFO( "imported $num_stories stories in $import_time seconds" );

        last if ( !$empty_queue && _stories_queue_is_small( $db ) );

        if ( $throttle )
        {
            INFO( "sleeping for $throttle seconds to throttle ..." );
            sleep( $throttle );
        }
    }
}

=head2 delete_all_stories

Delete all stories from the solr server.  Cowardly refuse if there are enough stories that this may be a
production server.

=cut

sub delete_all_stories($)
{
    my ( $db ) = @_;

    INFO "deleting all sentences ...";

    die( "Cowardly refusing to delete maybe production solr" ) if ( _maybe_production_solr( $db ) );

    my $url_params = { 'commit' => 'true', 'stream.body' => '<delete><query>*:*</query></delete>', };
    eval { _solr_request( $db, 'update', $url_params ); };
    if ( $@ )
    {
        my $error = $@;
        WARN "Error while deleting all stories: $error";
        return 0;
    }

    return 1;
}

=head2 queue_all_stories

Insert stories_ids for all processed stories into the stories queue table.

=cut

sub queue_all_stories($;$)
{
    my ( $db, $stories_queue_table ) = @_;

    _validate_using_test_db_with_test_index();

    $stories_queue_table //= $DEFAULT_STORIES_QUEUE_TABLE;

    $db->begin();

    $db->query( "truncate table $stories_queue_table" );

    # select from processed_stories because only processed stories should get imported.  sort so that the
    # the import is more efficient when pulling blocks of stories out.
    $db->query( <<SQL );
insert into $stories_queue_table
    select stories_id
        from processed_stories
        group by stories_id
        order by stories_id
SQL

    $db->commit();
}

1;
