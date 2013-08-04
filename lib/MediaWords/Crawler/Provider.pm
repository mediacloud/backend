package MediaWords::Crawler::Provider;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# provide one request at a time a crawler process

use strict;
use warnings;

use URI::Split;

use Data::Dumper;

use List::MoreUtils;
use MediaWords::DB;
use MediaWords::Crawler::Downloads_Queue;
use Readonly;
use Time::Seconds;
use Math::Random;

# how often to download each feed (seconds)
use constant STALE_FEED_INTERVAL => 3 * 4 * ONE_HOUR;

# how often to check for feeds to download (seconds)
use constant STALE_FEED_CHECK_INTERVAL => 30 * ONE_MINUTE;

# timeout for download in fetching state (seconds)
use constant STALE_DOWNLOAD_INTERVAL => 5 * ONE_MINUTE;

# how many downloads to store in memory queue
use constant MAX_QUEUED_DOWNLOADS => 50000;

# how many queued downloads mean the queue is more or less idle
# and thus can be filled with missing downloads
use constant QUEUED_DOWNLOADS_IDLE_COUNT => 1000;

# how many missing downloads to enqueue each and every time the queue is idle
# (has to fit in memory because this is how much downloads are passed to
# _queue_download_list_with_per_site_limit())
use constant MISSING_DOWNLOADS_CHUNK_COUNT => 1000;

# how often to check the database for new pending downloads (seconds)
use constant DEFAULT_PENDING_CHECK_INTERVAL => 10 * ONE_MINUTE;

# last time a stale feed check was run
my $_last_stale_feed_check = 0;

# last time a stale download check was run
my $_last_stale_download_check = 0;

my $_last_timed_out_spidered_download_check = 0;

# last time a pending downloads check was run
my $_last_pending_check = 0;

# has setup run once?
my $_setup = 0;

# hash of { $download_media_id => { time => $last_request_time_for_media_id,
#                                   pending => $pending_downloads }  }
my $_downloads = {};

Readonly my $download_timed_out_error_message => 'Download timed out by Fetcher::_timeout_stale_downloads';

my $_serializer;
my $_downloads_count = 0;

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );

    $self->{ downloads } = MediaWords::Crawler::Downloads_Queue->new();
    return $self;
}

# run before forking engine to perform one time setup tasks
sub _setup
{
    my ( $self ) = @_;

    if ( !$_setup )
    {
        print STDERR "Provider _setup\n";
        $_setup = 1;

        $self->engine->dbs->query( "UPDATE downloads set state = 'pending' where state = 'fetching'" );
    }
}

# delete downloads in fetching mode more than five minutes old.
# this shouldn't technically happen, but we want to make sure that
# no hosts get hung b/c a download sits around in the fetching state forever
sub _timeout_stale_downloads
{
    my ( $self ) = @_;

    if ( $_last_stale_download_check > ( time() - STALE_DOWNLOAD_INTERVAL ) )
    {
        return;
    }
    $_last_stale_download_check = time();

    my $dbs       = $self->engine->dbs;
    my @downloads = $dbs->query(
        "SELECT * from downloads_media where state = 'fetching' and download_time < (now() - interval '5 minutes')" )
      ->hashes;

    for my $download ( @downloads )
    {
        $download->{ state }         = ( 'error' );
        $download->{ error_message } = ( $download_timed_out_error_message );
        $download->{ download_time } = ( 'now()' );

        $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );

        print STDERR "timed out stale download " . $download->{ downloads_id } . " for url " . $download->{ url } . "\n";
    }

}

# get all stale feeds and add each to the download queue
# this subroutine expects to be executed in a transaction
sub _add_stale_feeds
{
    my ( $self ) = @_;

    if ( ( time() - $_last_stale_feed_check ) < STALE_FEED_CHECK_INTERVAL )
    {
        return;
    }

    print STDERR "start _add_stale_feeds\n";

    $_last_stale_feed_check = time();

    my $dbs = $self->engine->dbs;

    my $last_new_story_time_clause =
" ( now() > last_attempted_download_time + ( last_attempted_download_time - last_new_story_time ) + interval '5 minutes' ) ";

    my $constraint =
      "((last_attempted_download_time IS NULL " . "OR (last_attempted_download_time < (NOW() - interval ' " .
      STALE_FEED_INTERVAL . " seconds')) OR $last_new_story_time_clause ) " . "AND url ~ 'https?://')";

    my $feeds = $dbs->query( <<END )->hashes;
UPDATE feeds SET last_attempted_download_time = now()
    WHERE $constraint
    RETURNING *
END

  DOWNLOAD:
    for my $feed ( @{ $feeds } )
    {
        ##TODO add a constraint to the fields table in the database to ensure that the URL is valid
        next DOWNLOAD if ( !$feed->{ url } || !( $feed->{ url } =~ /^https?:\/\//i ) );

        my $download = _create_download_for_feed( $feed, $dbs );

        $download->{ _media_id } = $feed->{ media_id };

        $self->{ downloads }->_queue_download( $download );
    }

    print STDERR "end _add_stale_feeds\n";

}

sub _create_download_for_feed
{
    my ( $feed, $dbs ) = @_;

    my $priority = 0;
    if ( !$feed->{ last_attempted_download_time } )
    {
        $priority = 10;
    }

    my $host = lc( ( URI::Split::uri_split( $feed->{ url } ) )[ 1 ] );
    my $download = $dbs->create(
        'downloads',
        {
            feeds_id      => $feed->{ feeds_id },
            url           => $feed->{ url },
            host          => $host,
            type          => 'feed',
            sequence      => 1,
            state         => 'pending',
            priority      => $priority,
            download_time => 'now()',
            extracted     => 'f'
        }
    );

    return $download;
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

#TODO combine _queue_download_list & _queue_download_list_per_site_limit
sub _queue_download_list_with_per_site_limit
{
    my ( $self, $downloads, $site_limit ) = @_;

    my $queued_downloads = [];

    for my $download ( @{ $downloads } )
    {
        my $site = MediaWords::Crawler::Downloads_Queue::get_download_site_from_hostname( $download->{ host } );

        my $site_queued_download_count = $self->{ downloads }->_get_queued_downloads_count( $site, 1 );

        next if ( $site_queued_download_count > $site_limit );

        push( @{ $queued_downloads }, $download );

        $self->{ downloads }->_queue_download( $download );
    }

    # my $downloads_id_list = join( ',', map { $_->{ downloads_id } } @{ $queued_downloads } );
    # $self->engine->dbs->query( "update downloads set state = 'queued' where downloads_id in ($downloads_id_list)" );

    return;
}

# add missing downloads
sub _add_missing_downloads($$)
{
    my ( $self, $missing_downloads_chunk_count ) = @_;

    unless ( $missing_downloads_chunk_count )
    {
        say STDERR "Missing downloads chunk count is 0";
        return;
    }

    say STDERR "adding missing downloads";

    my $db = $self->engine->dbs;

    # Enqueue some of the missing downloads to the redownloaded
    my $missing_downloads = $db->query(
        <<END,
        SELECT d.*,
               f.media_id AS _media_id,
               COALESCE( site_from_host( d.host ), 'non-media' ) AS site
        FROM downloads AS d
            LEFT JOIN feeds AS f ON f.feeds_id = d.feeds_id

        -- enqueue only "content" downloads, skip the "feed" downloads
        -- (because we do not expect we will get the same feed as it was
        -- in 2009)
        WHERE d.type = 'content'

          -- and the download is missing from the filesystem
          AND d.file_status = 'missing'

          -- the download was successful the first time it was fetched
          -- (do not attempt to redownload errorneous downloads)
          AND d.state = 'success'
        ORDER BY downloads_id ASC
        LIMIT ?
END
        $missing_downloads_chunk_count
    )->hashes;

    my $missing_download_sites = [ List::MoreUtils::uniq( map { $_->{ site } } @{ $missing_downloads } ) ];

    my $site_missing_downloads = {};
    map { push( @{ $site_missing_downloads->{ $_->{ site } } }, $_ ) } @{ $missing_downloads };

    if ( @{ $missing_download_sites } )
    {
        my $site_missing_download_queue_limit = int( MAX_QUEUED_DOWNLOADS / scalar( @{ $missing_download_sites } ) );

        for my $missing_download_site ( @{ $missing_download_sites } )
        {
            $self->_queue_download_list_with_per_site_limit( $site_missing_downloads->{ $missing_download_site },
                $site_missing_download_queue_limit );
        }
    }
}

# add all pending downloads to the $_downloads list
sub _add_pending_downloads
{
    my ( $self ) = @_;

    my $interval = $self->engine->pending_check_interval || DEFAULT_PENDING_CHECK_INTERVAL;

    return if ( $_last_pending_check > ( time() - $interval ) );

    $_last_pending_check = time();

    if ( $self->{ downloads }->_get_downloads_size > MAX_QUEUED_DOWNLOADS )
    {
        print STDERR "skipping add pending downloads due to queue size\n";
        return;
    }

    my $db = $self->engine->dbs;

    my $downloads = $db->query(
        <<END,
        SELECT d.*,
               f.media_id AS _media_id,
               COALESCE( site_from_host( d.host ), 'non-media' ) AS site
        FROM downloads AS d
            LEFT JOIN feeds AS f ON f.feeds_id = d.feeds_id
        WHERE state = 'pending'
        ORDER BY downloads_id ASC
        LIMIT ?
END
        MAX_QUEUED_DOWNLOADS
    )->hashes;

    my $sites = [ List::MoreUtils::uniq( map { $_->{ site } } @{ $downloads } ) ];

    my $site_downloads = {};
    map { push( @{ $site_downloads->{ $_->{ site } } }, $_ ) } @{ $downloads };

    if ( @{ $sites } )
    {
        my $site_download_queue_limit = int( MAX_QUEUED_DOWNLOADS / scalar( @{ $sites } ) );

        for my $site ( @{ $sites } )
        {
            $self->_queue_download_list_with_per_site_limit( $site_downloads->{ $site }, $site_download_queue_limit );
        }
    }
}

# add all pending downloads to the $_downloads list
sub _retry_timed_out_spider_downloads
{
    my ( $self ) = @_;

    my $interval = $self->engine->pending_check_interval || DEFAULT_PENDING_CHECK_INTERVAL;

    $interval *= 20;

    if ( $_last_timed_out_spidered_download_check > ( time() - $interval ) )
    {
        return;
    }

    print STDERR "start _retry_timed_out_spider_downloads\n";

    $_last_timed_out_spidered_download_check = time();

    $self->engine->dbs->query(
"update downloads set (state,error_message) = ('pending','') where state='error' and type in ('spider_blog_home','spider_posting','spider_rss','spider_blog_friends_list') and (error_message like '50%' or error_message = '$download_timed_out_error_message') ;"
    );

    print STDERR "end _retry_timed_out_spider_downloads\n";
}

# return the next pending request from the downloads table
# that meets the throttling requirement
sub provide_downloads
{
    my ( $self ) = @_;

    sleep( 1 );

    $self->_setup();

    $self->_timeout_stale_downloads();

    # $self->engine->dbs->transaction(sub { $self->_add_stale_feeds(); });
    $self->_add_stale_feeds();

    #$self->_retry_timed_out_spider_downloads();
    $self->_add_pending_downloads();

    # Add some missing downloads if the functions above didn't fill up the queue
    if ( $self->{ downloads }->_get_downloads_size < QUEUED_DOWNLOADS_IDLE_COUNT )
    {
        $self->_add_missing_downloads( MISSING_DOWNLOADS_CHUNK_COUNT );
    }

    my @downloads;
  MEDIA_ID:
    for my $media_id ( @{ $self->{ downloads }->_get_download_media_ids } )
    {

        # we just slept for 1 so only bother calling time() if throttle is greater than 1
        if ( ( $self->engine->throttle > 1 ) && ( $media_id->{ time } > ( time() - $self->engine->throttle ) ) )
        {

            print STDERR "provide downloads: skipping media id $media_id->{media_id} because of throttling\n";

            #skip;
            next MEDIA_ID;
        }

        foreach ( 1 .. 3 )
        {
            if ( my $download = $self->{ downloads }->_pop_download( $media_id->{ media_id } ) )
            {
                push( @downloads, $download );
            }
        }
    }

    print STDERR "provide downloads: " . scalar( @downloads ) . " downloads\n";

    if ( !@downloads )
    {
        sleep( 10 );
    }

    return \@downloads;
}

# calling engine
sub engine
{
    if ( $_[ 1 ] )
    {
        $_[ 0 ]->{ engine } = $_[ 1 ];
    }

    return $_[ 0 ]->{ engine };
}

1;
