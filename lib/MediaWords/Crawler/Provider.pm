package MediaWords::Crawler::Provider;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::Crawler::Provider - provision downloads for the crawler engine's in memory downloads queue

=head1 SYNOPSIS

    # this is a simplified version of the code used by $engine->crawl() to interact with the crawler provider

    my $crawler = MediaWords::Crawler::Engine->new();

    my $provider = MediaWords::Crawler::Provider->new( $crawler );

    my $queued_downloads;
    while ( 1 )
    {
        if ( !@{ $queued_downloads } )
        {
            $queued_downloads = $provider->provide_downloads();
        }

        my $download = shift( @{ $queued_downloads } );
        # hand out a download
    }

=head1 DESCRIPTION

The provider is responsible for provisioning downloads for the engine's in memory downloads queue.  The basic job
of the provider is just to query the downloads table for any downloads with `state = 'pending'`.  As detailed in the
handler section below, most 'pending' downloads are added by the handler when the url for a new story is discovered
in a just download feed.

But the provider is also responsible for periodically adding feed downloads to the queue.  The provider uses a back off
algorithm that starts by downloading a feed five minutes after a new story was last found and then doubles the delay
each time the feed is download and no new story is found, until the feed is downloaded only once a week.

The provider is also responsible for throttling downloads by site, so only a limited number of downloads for each site
are provided to the the engine each time the engine asks for a chunk of new downloads.

=cut

use strict;
use warnings;

use Data::Dumper;
use Readonly;

use MediaWords::DB;
use MediaWords::Crawler::Downloads_Queue;
use MediaWords::Util::Config;

# how often to download each feed (seconds)
Readonly my $STALE_FEED_INTERVAL => 60 * 60 * 24 * 7;

# how often to check for feeds to download (seconds)
Readonly my $STALE_FEED_CHECK_INTERVAL => 60 * 30;

# timeout for download in fetching state (seconds)
Readonly my $STALE_DOWNLOAD_INTERVAL => 60 * 5;

# how many downloads to store in memory queue
Readonly my $MAX_QUEUED_DOWNLOADS => 100_000;

# how many downloads per site to story in memory queue
Readonly my $MAX_QUEUED_DOWNLOADS_PER_SITE => 1_000;

# how often to check the database for new pending downloads (seconds)
Readonly my $DEFAULT_PENDING_CHECK_INTERVAL => 60;

Readonly my $DOWNLOAD_TIMED_OUT_ERROR_MESSAGE => 'Download timed out by Fetcher::_timeout_stale_downloads';

=head1 METHODS

=head2 new

Create a new provider.  Must pass a MediaWords::Crawler::Engine object.

=cut

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );

    # last time a pending downloads check was run
    $self->{ last_pending_check } = 0;

    # last time a stale feed check was run
    $self->{ last_stale_feed_check } = 0;

    # last time a stale download check was run
    $self->{ last_stale_download_check } = 0;

    # has setup run once?
    $self->{ setup_was_run } = 0;

    return $self;
}

# run before forking engine to perform one time setup tasks
sub _setup
{
    my ( $self ) = @_;

    unless ( $self->{ setup_was_run } )
    {
        TRACE( "_setup" );
        $self->{ setup_was_run } = 1;

        $self->engine->dbs->query( "UPDATE downloads set state = 'pending' where state = 'fetching'" );
    }
}

# delete downloads in fetching mode more than five minutes old.
# this shouldn't technically happen, but we want to make sure that
# no hosts get hung b/c a download sits around in the fetching state forever
sub _timeout_stale_downloads
{
    my ( $self ) = @_;

    if ( $self->{ last_stale_download_check } > ( time() - $STALE_DOWNLOAD_INTERVAL ) )
    {
        return;
    }
    $self->{ last_stale_download_check } = time();

    my $dbs = $self->engine->dbs;
    $dbs->query( <<SQL, $DOWNLOAD_TIMED_OUT_ERROR_MESSAGE );
update downloads_p set
        state = 'error',
        error_message = ?,
        download_time = now()
    where
        state = 'fetching' and
        download_time < now() - interval '5 minutes'
SQL

}

# add pending downloads for all stale feeds
sub _add_stale_feeds
{
    my ( $self ) = @_;

    if ( ( time() - $self->{ last_stale_feed_check } ) < $STALE_FEED_CHECK_INTERVAL )
    {
        return;
    }

    my $stale_feed_interval = $STALE_FEED_INTERVAL;

    $self->{ last_stale_feed_check } = time();

    my $dbs = $self->engine->dbs;

    # If the table doesn't exist, PostgreSQL sends a NOTICE which breaks the "no warnings" unit test
    $dbs->query( 'SET client_min_messages=WARNING' );
    $dbs->query( 'DROP TABLE IF EXISTS feeds_to_queue' );
    $dbs->query( 'SET client_min_messages=NOTICE' );

    $dbs->query( <<"SQL" );
        CREATE TEMPORARY TABLE feeds_to_queue AS
        SELECT feeds_id,
               url
        FROM feeds
        WHERE active = 't'
          AND url ~ 'https?://'
          AND (
            -- Never attempted
            last_attempted_download_time IS NULL

            -- Feed was downloaded more than $stale_feed_interval seconds ago
            OR (last_attempted_download_time < (NOW() - interval '$stale_feed_interval seconds'))

            -- (Probably) if a new story comes in every "n" seconds, refetch feed every "n" + 5 minutes
            OR (
                (NOW() > last_attempted_download_time + ( last_attempted_download_time - last_new_story_time ) + interval '5 minutes')

                -- "web_page" feeds are to be downloaded only once a week,
                -- independently from when the last new story comes in from the
                -- feed (because every "web_page" feed download provides a
                -- single story)
                AND type != 'web_page'
            )
          )
SQL

    $dbs->query( <<"SQL" );
        UPDATE feeds
        SET last_attempted_download_time = NOW()
        WHERE feeds_id IN (SELECT feeds_id FROM feeds_to_queue)
SQL

    my $downloads = $dbs->query( <<"SQL" )->hashes;
    WITH inserted_downloads as (
        INSERT INTO downloads (feeds_id, url, host, type, sequence, state, priority, download_time, extracted)
        SELECT feeds_id,
               url,
               LOWER(SUBSTRING(url from '.*://([^/]*)' )),
               'feed',
               1,
               'pending',
               0,
               NOW(),
               false
        FROM feeds_to_queue
        RETURNING *
    )

    select d.*, f.media_id as _media_id
        from inserted_downloads d
            join feeds f using ( feeds_id )
SQL

    $dbs->query( "drop table feeds_to_queue" );

    DEBUG "added stale feeds: " . scalar( @{ $downloads } );
}

# add most recent $MAX_QUEUED_DOWNLOADS pending downloads to the $_downloads list,
# limit to $MAX_QUEUED_DOWNLOADS_PER_SITE downloads per downloads.host.
sub _add_pending_downloads
{
    my ( $self ) = @_;

    my $interval = $self->engine->pending_check_interval || $DEFAULT_PENDING_CHECK_INTERVAL;

    return if ( !$self->engine->test_mode && ( $self->{ last_pending_check } > ( time() - $interval ) ) );

    $self->{ downloads } = MediaWords::Crawler::Downloads_Queue->new();

    $self->{ last_pending_check } = time();

    if ( $self->{ downloads }->_get_downloads_size > $MAX_QUEUED_DOWNLOADS )
    {
        DEBUG "skipping add pending downloads due to queue size";
        return;
    }

    my $db = $self->engine->dbs;

    my ( $num_pending_downloads ) = $db->query( <<SQL )->flat();
select n_live_tup from pg_stat_user_tables where schemaname = 'public' and relname = 'downloads_p_pending'
SQL

    # sample_size is used in query below to generate a random sample of all of the rows in the
    # download_p_pending table, so that the crawler uses a good diversity of media sources and thereby
    # does not get stuck heavily throttling a small number of recent sources
    my $sample_size = ( $MAX_QUEUED_DOWNLOADS / ++$num_pending_downloads ) * 100;
    $sample_size = List::Util::min( $sample_size, 10 );

    DEBUG( "pending downloads sample size: $sample_size" );

    my $downloads = $db->query( <<END, $MAX_QUEUED_DOWNLOADS, $sample_size )->hashes();
with pending_downloads as (
    select * from ( select * from downloads_p_pending order by downloads_p_id desc limit ? ) q
    union
    select * from downloads_p_pending tablesample system ( ? )
)

select
        d.*,
        d.downloads_p_id downloads_id,
        coalesce( d.host, 'non-media' ) site,
        f.media_id _media_id
    from pending_downloads d
        join feeds f using ( feeds_id )
    where
        ( d.download_time < now() or d.download_time is null )
    order by downloads_id desc
END

    DEBUG( "total pending downloads: " . scalar( @{ $downloads } ) );

    my $num_queued           = 0;
    my $num_unqueued_printed = 0;
    for my $download ( @{ $downloads } )
    {
        my $queued = $self->{ downloads }->_queue_download( $download );
        $num_queued += $queued;
        if ( !$queued && $num_unqueued_printed++ < 3 )
        {
            DEBUG( "queue failed for download $download->{ downloads_id }" );
        }
    }

    DEBUG( "pending downloads queued: $num_queued" );
}

=head2 provide_downloads

Hand out a list of pending downloads, throttling the downloads by site (download host, generally), so that a download is
only handed our for each site each $self->engine->throttle seconds.

Every $STALE_FEED_INTERVAL, add downloads for all feeds that are due to be downloaded again according to
the back off algorithm.

Every $self->engine->pending_check_interval seconds, query the database for pending downloads (`state = 'pending'`).

=cut

sub provide_downloads
{
    my ( $self ) = @_;

    # It appears that the provider is sleep()ing while waiting for the "engine"
    # to process a single download, and if the queue is not yet finished at the
    # end of the sleep(), provider will refuse to provide any downloads.
    #
    # In its original iteration, provide_downloads() was sleeping for 1 second
    # before continuing, but UserAgent()'s rewrite made fetch_download()
    # + handle_download() slightly slower, so now the sleep() period has been
    # slightly increased.
    sleep( 5 ) if $self->engine->test_mode;

    $self->_setup();

    $self->_timeout_stale_downloads();

    $self->_add_stale_feeds();

    $self->_add_pending_downloads();

    my @downloads;
    my $num_skips = 0;

    my $queued_media_ids = $self->{ downloads }->_get_download_media_ids();

    DEBUG( "provide downloads queued media ids: " . scalar( @{ $queued_media_ids } ) );

  MEDIA_ID:
    for my $media_id ( @{ $queued_media_ids } )
    {
        # we just slept for 1 so only bother calling time() if throttle is greater than 1
        if ( ( $self->engine->throttle >= 1 ) && ( $media_id->{ time } > ( time() - $self->engine->throttle ) ) )
        {

            TRACE "provide downloads: skipping media id $media_id->{media_id} because of throttling";

            $num_skips++;

            #skip;
            next MEDIA_ID;
        }

        if ( my $download = $self->{ downloads }->_pop_download( $media_id->{ media_id } ) )
        {
            push( @downloads, $download );
        }
    }

    DEBUG "skipped / throttled downloads: $num_skips" if ( $num_skips > 0 );
    DEBUG "provide downloads: " . scalar( @downloads ) . " downloads";

    if ( !@downloads )
    {
        sleep( 1 ) unless $self->engine->test_mode;
    }

    return \@downloads;
}

=head2 engine

getset engine - the crawler engine calling the provider

=cut

sub engine
{
    if ( $_[ 1 ] )
    {
        $_[ 0 ]->{ engine } = $_[ 1 ];
    }

    return $_[ 0 ]->{ engine };
}

1;
