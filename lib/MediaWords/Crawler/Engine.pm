package MediaWords::Crawler::Engine;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

MediaWords::Crawler::Engine - controls and coordinates the work of the crawler provider, fetchers, and handlers

=head1 SYNOPSIS

    my $crawler_fetcher = MediaWords::Crawler::Engine->new();

    $crawler_fetcher->crawl();

=head1 DESCRIPTION

The crawler engine coordinates the work of a single crawler_fetcher process.  A crawler_fetcher sits in a polling
loop looking for new download_ids in queued_downloads and, when one is found, fetching and handling the given
download.

=cut

use strict;
use warnings;

use Data::Dumper;

use MediaWords::Crawler::Download::Content;
use MediaWords::Crawler::Download::Feed::Syndicated;
use MediaWords::Crawler::Download::Feed::WebPage;
use MediaWords::Crawler::Download::Feed::Univision;
use MediaWords::Util::Timing;

=head1 METHODS

=head2 new

Create new crawler engine object.

=cut

sub new
{
    my ( $class, $db ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->extract_in_process( 0 );

    die( 'database handle required' ) unless $db;

    $self->dbs( $db );

    return $self;
}

# (static) Returns correct handler for download
sub handler_for_download($$;$)
{
    my ( $db, $download, $handler_args ) = @_;

    $handler_args //= {};

    my $downloads_id  = $download->{ downloads_id };
    my $download_type = $download->{ type };

    my $handler;
    if ( $download_type eq 'feed' )
    {
        my $feeds_id  = $download->{ feeds_id };
        my $feed      = $db->find_by_id( 'feeds', $feeds_id );
        my $feed_type = $feed->{ type };

        if ( $feed_type eq 'syndicated' )
        {
            $handler = MediaWords::Crawler::Download::Feed::Syndicated->new( $handler_args );
        }
        elsif ( $feed_type eq 'web_page' )
        {
            $handler = MediaWords::Crawler::Download::Feed::WebPage->new( $handler_args );
        }
        elsif ( $feed_type eq 'univision' )
        {
            $handler = MediaWords::Crawler::Download::Feed::Univision->new( $handler_args );
        }
        else
        {
            LOGCONFESS "Unknown feed type '$feed_type' for feed $feeds_id, download $downloads_id";
        }

    }
    elsif ( $download_type eq 'content' )
    {
        $handler = MediaWords::Crawler::Download::Content->new( $handler_args );
    }
    else
    {
        LOGCONFESS "Unknown download type '$download_type' for download $downloads_id";
    }

    return $handler;
}

sub _fetch_and_handle_download($$$)
{
    my ( $self, $download, $handler ) = @_;

    my $url = $download->{ url };

    if ( !$download )
    {
        LOGDIE( "Unable to find download_id: $download->{downloads_id}" );
    }

    DEBUG "fetch: $download->{downloads_id} $url ...";

    my $db = $self->dbs;

    my $start_fetch_time = MediaWords::Util::Timing::start_time( 'fetch' );
    my $response = $handler->fetch_download( $db, $download );
    MediaWords::Util::Timing::stop_time( 'fetch', $start_fetch_time );

    my $start_handle_time = MediaWords::Util::Timing::start_time( 'handle' );
    $DB::single = 1;
    eval { $handler->handle_response( $db, $download, $response ); };
    if ( $@ )
    {
        LOGDIE( "Error in handle_response() for downloads_id $download->{downloads_id} $url : $@" );
    }
    MediaWords::Util::Timing::stop_time( 'handle', $start_handle_time );

    DEBUG "Fetcher $download->{downloads_id} $url done";

    return;
}

# poll queued_downloads for new downloads and call fetch_and_handle_download()
sub run_fetcher
{
    my ( $self, $no_daemon ) = @_;

    my $start_idle_time = MediaWords::Util::Timing::start_time( 'idle' );

    my $db = $self->dbs;

    while ( 1 )
    {
        my $download;

        eval {
            # the delete below can deadlock, so only do it once at a time
            while ( !MediaWords::DB::Locks::get_session_lock( $db, 'MediaWords::Crawler::Engine::run_fetcher', 0 ) )
            {
                DEBUG( "waiting for run_fetcher queued_downloads lock..." );
                sleep( 1 );
            }

            my ( $downloads_id ) = $db->query( <<SQL )->flat();
delete from queued_downloads where queued_downloads_id in 
        ( select queued_downloads_id from queued_downloads order by queued_downloads_id limit 1 )
    returning downloads_id
SQL

            MediaWords::DB::Locks::release_session_lock( $db, 'MediaWords::Crawler::Engine::run_fetcher', 0 );

            if ( $downloads_id )
            {
                $download = $db->find_by_id( 'downloads', $downloads_id );

                MediaWords::Util::Timing::stop_time( 'idle', $start_idle_time );

                my $handler = handler_for_download( $db, $download, { extract_in_process => $self->extract_in_process } );

                $self->_fetch_and_handle_download( $download, $handler );

                $start_idle_time = MediaWords::Util::Timing::start_time( 'idle' );
            }
            else
            {
                sleep( 1 );
            }
        };

        if ( $@ )
        {
            WARN "ERROR: $@";
            if ( $download && ( !grep { $_ eq $download->{ state } } ( 'fetching', 'queued' ) ) )
            {
                $download->{ state }         = 'error';
                $download->{ error_message } = $@;
                $self->dbs->update_by_id( 'downloads', $download->{ downloads_id }, $download );
            }
        }

        last if ( $no_daemon );
    }
}

=head2 extract_in_process

getset extract_in_process - whether extract downloads in crawler's process instead of sending them to the job broker

=cut

sub extract_in_process
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ extract_in_process } = $_[ 1 ];
    }

    return $_[ 0 ]->{ extract_in_process };
}

=head2 dbs

getset dbs - the engine MediaWords::DBI Simple handle

=cut

sub dbs
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ dbs } = $_[ 1 ];
    }

    return $_[ 0 ]->{ dbs };
}

1;
