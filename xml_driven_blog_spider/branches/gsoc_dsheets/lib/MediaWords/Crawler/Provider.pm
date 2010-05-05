package MediaWords::Crawler::Provider;

# provide one request at a time a crawler process

use strict;
use warnings;

use URI::Split;

use Data::Dumper;

use MediaWords::DBI::Feeds;
use MediaWords::DB;

# how often to download each feed (seconds)
use constant STALE_FEED_INTERVAL => 14400;

# how often to check for feeds to download (seconds)
use constant STALE_FEED_CHECK_INTERVAL => 600;

# timeout for download in fetching state (seconds)
use constant STALE_DOWNLOAD_INTERVAL => 300;

# how many downloads to store in memory queue
use constant MAX_QUEUED_DOWNLOADS => 10000;

# how often to check the database for new pending downloads (seconds)
use constant DEFAULT_PENDING_CHECK_INTERVAL => 60;

# last time a stale feed check was run
my $_last_stale_feed_check = 0;

# last time a stale download check was run
my $_last_stale_download_check = 0;

# last time a pending downloads check was run
my $_last_pending_check = 0;

# has setup run once?
my $_setup = 0;

# hash of { $download_media_id => { time => $last_request_time_for_media_id,
#                                   pending => $pending_downloads }  }
my $_downloads = {};

# hash of { $feed_id => $media_id}
my $_feed_media_ids = {};

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine($engine);

    return $self;
}

# run before forking engine to perform one time setup tasks
sub _setup
{
    my ($self) = @_;

    if ( !$_setup )
    {
        print STDERR "Provider _setup\n";
        $_setup = 1;

        my $dbs = $self->engine->dbs;

# $dbs->query("UPDATE downloads SET state = 'error', error_message = "
#. "'removed from queue at startup' WHERE (state = 'queued' or state='pending') "
#. "AND type = 'feed'");

        $dbs->query("UPDATE downloads set state = 'queued' where state = 'fetching'");

        my $dbs_result = $dbs->query("SELECT * from downloads where state =  'queued'");

        #print Dumper ($dbs);
        #print Dumper($dbs_result);

        my @queued_downloads = $dbs_result->hashes();

        print STDERR "Provider _setup queued_downloads array length = "
	    . scalar(@queued_downloads) . "\n";

        for my $d (@queued_downloads)
        {
            $self->_queue_download($d);
        }
    }
}

# # get the media_id for the given download, caching the result for each feed
# sub _get_download_media_id
# {
#     my ($download) = @_;
#
# #    print " start _get_download_media_id\n";
#
#     my $feeds_id = $download->get_column('feeds_id');
#
#     return _get_download_media_impl($feeds_id);
# }

##TODO refactor!!!
### This methods lives in both Provider & Handler
sub _get_download_media_impl
{
    my ( $self, $feeds_id ) = @_;

    if ( $_feed_media_ids->{$feeds_id} )
    {
        return $_feed_media_ids->{$feeds_id};
    }

    my $dbs = $self->engine->dbs;

    my ($media_id) = $dbs->query("SELECT media_id FROM feeds WHERE feeds_id = ?",
				 $feeds_id )->flat;
    
    $_feed_media_ids->{$feeds_id} = $media_id;

    return $media_id;
}

# # add a download to the queue
# sub _queue_dbix_download
# {
#     my ( $self, $download ) = @_;

#     return $self->_queue_download({$download->get_columns()});
# }

# add a download to the queue
sub _queue_download
{
    my ( $self, $download ) = @_;

    my $media_id = $self->_get_download_media_impl( $download->{feeds_id} );

    #print STDERR "Provider _queue_download media_id $media_id\n";

    $_downloads->{$media_id}->{queued} ||= [];
    $_downloads->{$media_id}->{time}   ||= 0;

    my $pending = $_downloads->{$media_id}->{queued};
    if ( $download->{priority} && ( $download->{priority} > 0 ) )
    {
        unshift( @{$pending}, $download );
    }
    else
    {
        push( @{$pending}, $download );
    }
}

# pop the latest download for the given media_id off the queue
sub _pop_download
{
    my ( $self, $media_id ) = @_;
    $_downloads->{$media_id}->{time} = time();

    $_downloads->{$media_id}->{queued} ||= [];

    return shift( @{ $_downloads->{$media_id}->{queued} } );
}

# get list of download media_id times in the form of { media_id => $media_id, time => $time }
sub _get_download_media_ids
{
    my ($self) = @_;

    return [
        map { { media_id => $_, time => $_downloads->{$_}->{time} } }
          keys( %{$_downloads} )
    ];
}

# get total number of queued downloads
sub _get_downloads_size
{
    my ($self) = @_;

    my $download_count = 0;

    for my $a ( values( %{$_downloads} ) )
    {
        if ( @{ $a->{queued} } )
        {
            $download_count += scalar( @{ $a->{queued} } );
        }
    }

    return $download_count;
}

# delete downloads in fetching mode more than five minutes old.
# this shouldn't technically happen, but we want to make sure that
# no hosts get hung b/c a download sits around in the fetching state forever
sub _timeout_stale_downloads
{
    my ($self) = @_;

    if ( $_last_stale_download_check > ( time() - STALE_DOWNLOAD_INTERVAL ) )
    {
        return;
    }
    $_last_stale_download_check = time();

    my $dbs = $self->engine->dbs;
    my @downloads =
	$dbs->query("SELECT * FROM downloads WHERE state = 'fetching' "
		    . "AND download_time < (now() - interval '5 minutes')")
	->hashes;

    for my $download (@downloads)
    {
        $download->{state}         = ('error');
        $download->{error_message} = ('Download timed out by '
				      . 'Fetcher::_timeout_stale_downloads');
        $download->{download_time} = ('now()');

        $dbs->update_by_id( "downloads", $download->{downloads_id}, $download );

        print STDERR "timed out stale download " . $download->{downloads_id}
	. " for url " . $download->{url} . "\n";
    }

}

# get all stale feeds and add each to the download queue
# this subroutine expects to be executed in a transaction
sub _add_stale_feeds
{
    my ($self) = @_;

    if ( ( time() - $_last_stale_feed_check ) < STALE_FEED_CHECK_INTERVAL )
    {
        return;
    }

    print STDERR "start _add_stale_feeds\n";

    $_last_stale_feed_check = time();

    my $dbs = $self->engine->dbs;

    my $constraint = "((last_download_time IS NULL "
	. "OR (last_download_time < (NOW() - interval ' "
	. STALE_FEED_INTERVAL
	. " seconds'))) "
	. "AND url LIKE 'http://%')";

    my $downloads_ids = $dbs->query("INSERT INTO downloads "
		. "(feeds_id, url, host, type, sequence, state, priority, "
		. "download_time, extracted) "
		. "SELECT feeds_id, url, "
		. "lower(substring(url from '//([^/?#]*)')) AS host, "
		. "'feed' AS type, 1 AS sequence, 'queued' AS state, "
		. "(CASE WHEN last_download_time IS NULL THEN 10 ELSE 0 END) "
		. "AS priority, NOW() AS download_time, 'f' AS extracted "
		. "FROM feeds WHERE url IS NOT NULL "
		. "AND " . $constraint . " RETURNING feeds_id, downloads_id")->map();

    my @feeds =
	$dbs->query("SELECT * FROM feeds WHERE " . $constraint)->hashes();

    $dbs->query("UPDATE feeds SET last_download_time=(NOW()"
		. "+ age(to_timestamp(CAST(random()*"
		. int(STALE_FEED_INTERVAL / 4) . " AS INTEGER)),"
		. " timestamp with time zone 'epoch'))"
		. "WHERE " . $constraint);

  DOWNLOAD:
    for my $feed (@feeds)
    {
        if ( !$feed->{url} || substr($feed->{url}, 0, 7) ne 'http://' )
        {
	    # TODO: report an error?
            next DOWNLOAD;
        }

        my $priority = 0;
        if ( !$feed->{last_download_time} )
        {
            MediaWords::DBI::Feeds::add_archive_feed_downloads( $dbs, $feed );
            $priority = 10;
        }

        my $host = lc( ( URI::Split::uri_split( $feed->{url} ) )[1] );
        my $download = 
	{
	    feeds_id      => $feed->{feeds_id},
	    downloads_id  => $downloads_ids->{$feed->{feeds_id}},
	    url           => $feed->{url},
	    host          => $host,
	    type          => 'feed',
	    sequence      => 1,
	    state         => 'queued',
	    priority      => $priority,
	    download_time => 'now()',
	    extracted     => 'f'
	};

        $self->_queue_download($download);
    }
    print STDERR "end _add_stale_feeds\n";
}

# add all pending downloads to the $_downloads list
sub _add_pending_downloads
{
    my ($self) = @_;

    my $interval = $self->engine->pending_check_interval || DEFAULT_PENDING_CHECK_INTERVAL;

    if ( $_last_pending_check > ( time() - $interval ) )
    {
        return;
    }
    $_last_pending_check = time();

    #if ((my $size = $self->_get_download_hosts_size) > MAX_QUEUED_DOWNLOADS) {
    #    print "skipping add pending downloads due to queue size ($size)\n";
    #    return;
    #}

    my @downloads =
	$self->engine->dbs->query("SELECT * FROM downloads "
				  . "WHERE state = 'pending' "
				  . "ORDER BY downloads_id desc limit ? ",
				  MAX_QUEUED_DOWNLOADS )->hashes;

    for my $download (@downloads)
    {
        $download->{state} = ('queued');
        $self->engine->dbs->update_by_id('downloads',
					 $download->{downloads_id},
					 $download);

        $self->_queue_download($download);
    }
}

# return the next pending request from the downloads table
# that meets the throttling requirement
sub provide_downloads
{
    my ($self) = @_;

    sleep(1);

    $self->_setup();

    $self->_timeout_stale_downloads();
    $self->engine->dbs->transaction(sub { $self->_add_stale_feeds(); });
    $self->_add_pending_downloads();

    my @downloads;
  MEDIA_ID:
    for my $media_id ( @{ $self->_get_download_media_ids } )
    {

        if ( $media_id->{time} > ( time() - $self->engine->throttle ) )
        {
	    
            print STDERR "provide downloads: skipping media id "
		. "$media_id->{media_id} because of throttling\n";
	    
            #skip;
            next MEDIA_ID;
        }

        if ( my $download = $self->_pop_download( $media_id->{media_id} ) )
        {
            push( @downloads, $download );
        }
    }

    print STDERR "provide downloads: " . scalar(@downloads) . " downloads\n";

    if ( !@downloads )
    {
        sleep(10);
    }

    return \@downloads;
}

# calling engine
sub engine
{
    if ( $_[1] )
    {
        $_[0]->{engine} = $_[1];
    }

    return $_[0]->{engine};
}

1;
