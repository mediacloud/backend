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
use List::MoreUtils;
use Math::Random;
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
Readonly my $MAX_QUEUED_DOWNLOADS => 10_000_000;

# how often to check the database for new pending downloads (seconds)
Readonly my $DEFAULT_PENDING_CHECK_INTERVAL => 60 * 10;

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

    $self->{ downloads } = MediaWords::Crawler::Downloads_Queue->new();

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

    my $dbs       = $self->engine->dbs;
    my @downloads = $dbs->query(
        "SELECT * from downloads_media where state = 'fetching' and download_time < (now() - interval '5 minutes')" )
      ->hashes;

    for my $download ( @downloads )
    {
        $download->{ state }         = ( 'error' );
        $download->{ error_message } = ( $DOWNLOAD_TIMED_OUT_ERROR_MESSAGE . '' );
        $download->{ download_time } = ( 'now()' );

        $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );

        DEBUG "timed out stale download " . $download->{ downloads_id } . "  " . $download->{ url };
    }

}

# get all stale feeds and add each to the download queue this subroutine expects to be executed in a transaction
sub _add_stale_feeds
{
    my ( $self ) = @_;

    if ( ( time() - $self->{ last_stale_feed_check } ) < $STALE_FEED_CHECK_INTERVAL )
    {
        return;
    }

    my $stale_feed_interval = $STALE_FEED_INTERVAL;

    DEBUG "_add_stale_feeds";

    $self->{ last_stale_feed_check } = time();

    my $dbs = $self->engine->dbs;

    my $constraint = <<"SQL";
SQL

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
                AND feed_type != 'web_page'
            )
          )
SQL

    $dbs->query( <<"SQL" );
        UPDATE feeds
        SET last_attempted_download_time = NOW()
        WHERE feeds_id IN (SELECT feeds_id FROM feeds_to_queue)
SQL

    my $downloads = $dbs->query( <<"SQL" )->hashes;
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
SQL

    for my $download ( @{ $downloads } )
    {
        my $medium = $dbs->query( "select media_id from feeds where feeds_id = ?", $download->{ feeds_id } )->hash;
        $download->{ _media_id } = $medium->{ media_id };
        $self->{ downloads }->_queue_download( $download );
    }

    $dbs->query( "drop table feeds_to_queue" );

    DEBUG "end _add_stale_feeds";

}

#TODO combine _queue_download_list & _queue_download_list_per_site_limit
sub _queue_download_list
{
    my ( $self, $downloads ) = @_;

    # my $downloads_id_list = join( ',', map { $_->{ downloads_id } } @{ $downloads } );
    # $self->engine->dbs->query( "update downloads set state = 'queued' where downloads_id in ($downloads_id_list)" );

    map { $self->{ downloads }->_queue_download( $_ ) } @{ $downloads };

    return;
}

# TODO combine _queue_download_list & _queue_download_list_per_site_limit
sub _queue_download_list_with_per_site_limit
{
    my ( $self, $downloads, $site_limit ) = @_;

    # temp fix to improve throughput for single media sources with large queues:
    # hard coding site limit to about the max we can handle per $DEFAULT_PENDING_CHECK_INTERVAL
    $site_limit = 25 * $DEFAULT_PENDING_CHECK_INTERVAL;

    DEBUG "queue " . scalar( @{ $downloads } ) . " downloads (site limit $site_limit)";

    my $queued_downloads = [];

    for my $download ( @{ $downloads } )
    {
        my $site = MediaWords::Crawler::Downloads_Queue::get_download_site_from_hostname( $download->{ host } );

        my $site_queued_download_count = $self->{ downloads }->_get_queued_downloads_count( $site, 1 );

        next if ( $site_queued_download_count > $site_limit );

        push( @{ $queued_downloads }, $download );

        $self->{ downloads }->_queue_download( $download );
    }

    DEBUG "queued " . scalar( @{ $queued_downloads } ) . " downloads";

    return;
}

# add all pending downloads to the $_downloads list
sub _add_pending_downloads
{
    my ( $self ) = @_;

    my $interval = $self->engine->pending_check_interval || $DEFAULT_PENDING_CHECK_INTERVAL;

    return if ( !$self->engine->test_mode && ( $self->{ last_pending_check } > ( time() - $interval ) ) );

    $self->{ last_pending_check } = time();

    if ( $self->{ downloads }->_get_downloads_size > $MAX_QUEUED_DOWNLOADS )
    {
        DEBUG "skipping add pending downloads due to queue size";
        return;
    }

    my $db = $self->engine->dbs;

    my $downloads = $db->query( <<END, $MAX_QUEUED_DOWNLOADS )->hashes;
select
        d.*,
        f.media_id _media_id,
        coalesce( d.host , 'non-media' ) site
    from downloads d
        join feeds f on ( d.feeds_id = f.feeds_id )
    where
        d.state = 'pending' and
        ( d.download_time < now() or d.download_time is null )
    order by priority asc
    limit ?
END

    my $sites = [ List::MoreUtils::uniq( map { $_->{ site } } @{ $downloads } ) ];

    my $site_downloads = {};
    map { push( @{ $site_downloads->{ $_->{ site } } }, $_ ) } @{ $downloads };

    if ( @{ $sites } )
    {
        my $site_download_queue_limit = int( $MAX_QUEUED_DOWNLOADS / scalar( @{ $sites } ) ) + 1;

        for my $site ( @{ $sites } )
        {
            $self->_queue_download_list_with_per_site_limit( $site_downloads->{ $site }, $site_download_queue_limit );
        }
    }
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

    # FIXME I wish I could explain what this sleep() from a commit in 2010 is for.
    #
    # "My guess is that this is related to the general awkwardness of testing
    # the multi-process crawler. The provider works on schedules of periodic
    # polling, so it will at times end up waiting for ten minutes until some
    # queued download is provided to the fetchers."
    #
    # "This works well for normal operation of the crawler but breaks testing
    # because we don't want to wait for the crawler to find some queued
    # download ten minutes to test whether it has been processed correctly.
    # There are some special configurations I added to the crawler to deal with
    # some of these issues, but my guess is that in other places I added some
    # brief waiting to make things work without special configuration."
    #
    # "The path of least immediate resistance is just to increase that sleep to
    # the minimum value to make the crawler tests pass consistently. There will
    # be some small impact on crawler performance in production because the
    # provider is effectively a single threaded bottleneck on the whole crawler
    # pool, so it's worth a little fiddling to make the wait as small as
    # possible to make the tests pass consistently."
    #
    # It appears that the provider is sleep()ing while waiting for the "engine"
    # to process a single download, and if the queue is not yet finished at the
    # end of the sleep(), provider will refuse to provide any downloads.
    #
    # In its original iteration, provide_downloads() was sleeping for 1 second
    # before continuing, but UserAgent()'s rewrite made fetch_download()
    # + handle_download() slightly slower, so now the sleep() period has been
    # slightly increased.
    sleep( 5 );

    $self->_setup();

    $self->_timeout_stale_downloads();

    $self->_add_stale_feeds();

    $self->_add_pending_downloads();

    my @downloads;
    my $num_skips = 0;

  MEDIA_ID:
    for my $media_id ( @{ $self->{ downloads }->_get_download_media_ids } )
    {

        # we just slept for 1 so only bother calling time() if throttle is greater than 1
        if ( ( $self->engine->throttle > 1 ) && ( $media_id->{ time } > ( time() - $self->engine->throttle ) ) )
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
        sleep( 10 ) unless $self->engine->test_mode;
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
