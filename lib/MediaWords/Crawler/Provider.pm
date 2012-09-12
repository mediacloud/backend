package MediaWords::Crawler::Provider;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# provide one request at a time a crawler process

use strict;
use warnings;

use URI::Split;

use Data::Dumper;
use Data::Serializer;
use Data::Random;

use List::MoreUtils;
use MediaWords::DB;
use MediaWords::Crawler::Downloads_Queue;
use Readonly;
use Time::Seconds;
use Math::Random;

# how often to check for feeds to download (seconds)
use constant STALE_FEED_CHECK_INTERVAL => 10 * ONE_MINUTE;

# timeout for download in fetching state (seconds)
use constant STALE_DOWNLOAD_INTERVAL => 5 * ONE_MINUTE;

# how many downloads to store in memory queue
use constant MAX_QUEUED_DOWNLOADS => 20000;

# how often to check the database for new pending downloads (seconds)
use constant DEFAULT_PENDING_CHECK_INTERVAL => ONE_MINUTE;

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

        my $dbs = $self->engine->dbs;

# $dbs->query("UPDATE downloads SET state = 'error', error_message = 'removed from queue at startup' where (state = 'queued' or state='pending') and type = 'feed'");

        #For the spider type download change these from queued to pending so that we don't load too much stuff into memory.
        #No obvious reason to just do this for spider type downloads but I haven't had a chance to test other stuff
        $dbs->query(
"UPDATE downloads set state = 'pending' where state = 'queued' and type in  ('spider_blog_home','spider_posting','spider_rss','spider_blog_friends_list','spider_validation_blog_home','spider_validation_rss')"
        );
        $dbs->query( "UPDATE downloads set state = 'queued' where state = 'fetching'" );

        my $dbs_result = $dbs->query( "SELECT * from downloads_media where state =  'queued'" );

        #print Dumper ($dbs);
        #print Dumper($dbs_result);

        my @queued_downloads = $dbs_result->hashes();

        $dbs_result = $dbs->query( "SELECT * from downloads_non_media where state =  'queued'" );
        push @queued_downloads, ( $dbs_result->hashes() );

        print STDERR "Provider _setup queued_downloads array length = " . scalar( @queued_downloads ) . "\n";

        for my $d ( @queued_downloads )
        {
            $self->{ downloads }->_queue_download( $d );
        }
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

# how often to download each feed (seconds)
use constant STALE_FEED_INTERVAL => 3 * 4 * ONE_HOUR;

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
      " ( now() > last_download_time + ( last_download_time - last_new_story_time ) + interval '5 minutes' ) ";

    my $constraint =
      "((last_download_time IS NULL " . "OR (last_download_time < (NOW() - interval ' " . STALE_FEED_INTERVAL .
      " seconds')) OR $last_new_story_time_clause ) " . "AND url ~ 'https?://')";

    Readonly my $feeds_query => "SELECT * FROM feeds WHERE " . $constraint;

    #say STDERR "$feeds_query";

    my @feeds = $dbs->query( $feeds_query )->hashes();

  DOWNLOAD:
    for my $feed ( @feeds )
    {
        ##TODO add a constraint to the fields table in the database to ensure that the URL is valid
        if ( !$feed->{ url }
            || ( ( substr( $feed->{ url }, 0, 7 ) ne 'http://' ) && ( substr( $feed->{ url }, 0, 8 ) ne 'https://' ) ) )
        {

            # TODO: report an error?
            next DOWNLOAD;
        }

        my $download = _create_download_for_feed( $feed, $dbs );

        $download->{ _media_id } = $feed->{ media_id };

        $self->{ downloads }->_queue_download( $download );

        # add a random skew to each feed so not every feed is downloaded at the same time
        my $skew = random_uniform_integer( 1, -1 * 5 * ONE_MINUTE, 5 * ONE_MINUTE );

        $feed->{ last_download_time } = \"now() + interval '$skew seconds'";

        #print STDERR "updating feed: " . $feed->{feeds_id} . "\n";

        $dbs->update_by_id( 'feeds', $feed->{ feeds_id }, $feed );
    }

    print STDERR "end _add_stale_feeds\n";

}

sub _create_download_for_feed
{
    my ( $feed, $dbs ) = @_;

    my $priority = 0;
    if ( !$feed->{ last_download_time } )
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
            state         => 'queued',
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

    for my $download ( @{ $downloads } )
    {
        $download->{ state } = ( 'queued' );
        $self->engine->dbs->update_by_id( 'downloads', $download->{ downloads_id }, $download );

        $self->{ downloads }->_queue_download( $download );
    }

    return;
}

#TODO combine _queue_download_list & _queue_download_list_per_site_limit
sub _queue_download_list_with_per_site_limit
{
    my ( $self, $downloads, $site_limit ) = @_;

    for my $download ( @{ $downloads } )
    {
        my $site = MediaWords::Crawler::Downloads_Queue::get_download_site_from_hostname( $download->{ host } );

        my $site_queued_download_count = $self->{ downloads }->_get_queued_downloads_count( $site, 1 );

        next if ( $site_queued_download_count > $site_limit );

        $download->{ state } = ( 'queued' );

        $self->engine->dbs->update_by_id( 'downloads', $download->{ downloads_id }, $download );

        $self->{ downloads }->_queue_download( $download );
    }

    return;
}

my $_pending_download_sites;

sub _get_pending_downloads_sites
{
    my ( $self ) = @_;

    if ( !$_pending_download_sites )
    {
        $_pending_download_sites =
          $self->engine->dbs->query( "SELECT distinct(site) from downloads_sites where state='pending' " )->flat();

        print "Updating _pending_download_sites\n";

        #print Dumper($_pending_download_sites);
    }

    return $_pending_download_sites;
}

# add all pending downloads to the $_downloads list
sub _add_pending_downloads
{
    my ( $self ) = @_;

    my $interval = $self->engine->pending_check_interval || DEFAULT_PENDING_CHECK_INTERVAL;

    if ( $_last_pending_check > ( time() - $interval ) )
    {
        return;
    }
    $_last_pending_check = time();

    my $current_queue_size = $self->{ downloads }->_get_downloads_size;
    if ( $current_queue_size > MAX_QUEUED_DOWNLOADS )
    {
        print "skipping add pending downloads due to queue size ($current_queue_size)\n";
        return;
    }

    print "Not skipping add pending downloads queue size($current_queue_size) \n";

    my @downloads_non_media =
      $self->engine->dbs->query( "SELECT * from downloads_non_media where state = 'pending' ORDER BY downloads_id limit ? ",
        int( int( MAX_QUEUED_DOWNLOADS ) / 2 ) )->hashes;
    $self->_queue_download_list_with_per_site_limit( \@downloads_non_media, 100000 );
    say "Queued " . scalar( @downloads_non_media ) . ' non_media downloads';

    my @sites = map { $_->{ media_id } } @{ $self->{ downloads }->_get_download_media_ids };

    #print Dumper(@sites);
    @sites = grep { $_ =~ /\./ } @sites;
    push( @sites, @{ $self->_get_pending_downloads_sites() } );
    @sites = List::MoreUtils::uniq( @sites );

    my @sites_with_queued_downloads = grep { $self->{ downloads }->_get_queued_downloads_count( $_, 1 ) > 0 } @sites;

    my $site_download_queue_limit = int( int( MAX_QUEUED_DOWNLOADS ) / ( scalar( @sites ) + 1 ) );

    my @downloads =
      $self->engine->dbs->query( "SELECT * from downloads_media where state = 'pending' ORDER BY downloads_id asc limit ? ",
        int( int( MAX_QUEUED_DOWNLOADS ) / 10 ) )->hashes;
    $self->_queue_download_list_with_per_site_limit( \@downloads, $site_download_queue_limit );

    @downloads =
      $self->engine->dbs->query( "SELECT * from downloads_media where state = 'pending' ORDER BY RANDOM() limit ? ",
        int( int( MAX_QUEUED_DOWNLOADS ) / 20 ) )->hashes;
    $self->_queue_download_list_with_per_site_limit( \@downloads, $site_download_queue_limit );

    for my $site ( @sites )
    {
        my $site_queued_downloads = $self->{ downloads }->_get_queued_downloads_count( $site, 1 );
        my $site_downloads_to_fetch = $site_download_queue_limit - $site_queued_downloads;

        next if ( $site_downloads_to_fetch < 0 );

        my @site_downloads = $self->_get_pending_downloads_for_site( $site, $site_downloads_to_fetch );

        #print "Site: '$site' downloads\n";
        #print Dumper(\@site_downloads);
        $self->_queue_download_list( \@site_downloads );
    }
}

sub _get_pending_downloads_for_site
{
    my ( $self, $site, $max_downloads ) = @_;

    my @site_downloads = $self->engine->dbs->query(
        "SELECT * from downloads_sites where site = ? and state = 'pending' ORDER BY downloads_id limit ? ",
        $site, $max_downloads )->hashes;

    #rip out the 'site' field since this isn't part of the downloads table
    for my $site_download ( @site_downloads )
    {
        delete( $site_download->{ site } );
    }

    return @site_downloads;
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
