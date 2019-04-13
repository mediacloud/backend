package MediaWords::Crawler::Engine;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

MediaWords::Crawler::Engine - controls and coordinates the work of the crawler provider, fetchers, and handlers

=head1 SYNOPSIS

    my $crawler = MediaWords::Crawler::Engine->new();

    $crawler->processes( 30 );
    $crawler->throttle( 1 );
    $crawler->sleep_interval( 10 );

    $crawler->crawl();

=head1 DESCRIPTION

The crawler engine coordinates the work of the provider and the fetcher/handler processes.  It first forks the specified
number of fetcher/handler processes and opens a socket connection to each of those processes. It then listens for
requests from each of those processes.  Each fetcher/handler process works in a loop of requesting  a url from the
engine process, dealing with that url, and then fetching another url from the engine.

The engine keeps in memory a queue of urls to download, handing out each queued url to a fetcher/handler
process when requested.  When the in memory queue of urls runs out, the engine calls the provider library to generate
a list of downloads to keep in the memory queue.

=cut

use strict;
use warnings;

use Fcntl;
use IO::Select;
use IO::Socket;
use Data::Dumper;

use MediaWords::DB;
use MediaWords::Crawler::Download::Content;
use MediaWords::Crawler::Download::Feed::Syndicated;
use MediaWords::Crawler::Download::Feed::WebPage;
use MediaWords::Crawler::Download::Feed::Univision;
use MediaWords::Crawler::Provider;
use MediaWords::Util::Process;
use MediaWords::Util::Timing;

=head1 METHODS

=head2 new

Create new crawler engine object.

=cut

sub new
{
    my ( $class ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->_reconnect_db();

    $self->processes( 1 );
    $self->sleep_interval( 60 );
    $self->throttle( 30 );
    $self->fetchers( [] );
    $self->children_exit_on_kill( 0 );
    $self->test_mode( 0 );

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
        LOGDIE( "fetch " . $self->fetcher_number . ": Unable to find download_id: $download->{downloads_id}" );
    }

    DEBUG "fetch " . $self->fetcher_number . ": $download->{downloads_id} $url ...";

    my $db = $self->dbs;

    my $start_fetch_time = MediaWords::Util::Timing::start_time( 'fetch' );
    my $response = $handler->fetch_download( $db, $download );
    MediaWords::Util::Timing::stop_time( 'fetch', $start_fetch_time );

    my $start_handle_time = MediaWords::Util::Timing::start_time( 'handle' );
    eval { $handler->handle_response( $db, $download, $response ); };
    if ( $@ )
    {
        LOGDIE( "Error in handle_response() for downloads_id $download->{downloads_id} $url : $@" );
    }
    MediaWords::Util::Timing::stop_time( 'handle', $start_handle_time );

    DEBUG "Fetcher " . $self->fetcher_number . ": $download->{downloads_id} $url done";

    return;
}

=head2 fetch_and_handle_single_download

Fetch and handle only a single download.  Useful mostly for testing.

=cut

sub fetch_and_handle_single_download
{

    my ( $self, $download ) = @_;

    $self->_reconnect_db();

    my $db = $self->dbs;

    my $handler = handler_for_download( $db, $download );
    $self->_fetch_and_handle_download( $download, $handler );

    return;
}

# continually loop through the provide, fetch, respond cycle for one crawler process
sub _run_fetcher
{
    my ( $self ) = @_;

    DEBUG "fetch " . $self->fetcher_number . " crawl loop";

    $self->_reconnect_db();

    $self->socket->blocking( 0 );

    my $start_idle_time = MediaWords::Util::Timing::start_time( 'idle' );

    while ( 1 )
    {
        my $download;

        eval {

            $download = 0;

            $self->_reconnect_db();

            my $db = $self->dbs;

            # tell the parent provider we're ready for another download
            # and then read the download id from the socket
            $self->socket->printflush( $self->fetcher_number() . "\n" );
            my $downloads_id = 0;
            $downloads_id = $self->socket->getline();

            if ( defined( $downloads_id ) )
            {
                chomp( $downloads_id );
            }

            if ( $downloads_id && ( $downloads_id ne 'none' ) && ( $downloads_id ne 'exit' ) )
            {
                $download = $db->find_by_id( 'downloads', $downloads_id );

                MediaWords::Util::Timing::stop_time( 'idle', $start_idle_time );

                my $handler = handler_for_download( $db, $download );

                $self->_fetch_and_handle_download( $download, $handler );

                $start_idle_time = MediaWords::Util::Timing::start_time( 'idle' );
            }
            elsif ( $downloads_id && ( $downloads_id eq 'exit' ) )
            {
            }
            else
            {
                TRACE "fetch " . $self->fetcher_number . " _run_fetcher sleeping ...";
                sleep( 1 );
            }
        };

        if ( $@ )
        {
            WARN "ERROR: fetcher " . $self->fetcher_number . ":\n****\n$@\n****";
            if ( $download && ( !grep { $_ eq $download->{ state } } ( 'fetching', 'queued' ) ) )
            {
                $download->{ state }         = 'error';
                $download->{ error_message } = $@;
                $self->dbs->update_by_id( 'downloads', $download->{ downloads_id }, $download );
            }

        }

    }
}

my $_exit_on_kill = 0;

sub _exit()
{
    exit();
}

=head2 _spawn_fetchers()

Fork off $self->process number of fetching processes.  For each forked fetching process, create socket between the
parent and child process.  In each child process, take care to reconnect to db and then enter an infinite
fetch/handle loop that:

=over

=item *

requests a new download id from the engine parent process via the parent/child socket;

=item *

calls $handler->fetch_download to get an http response for a download;

=item *

calls $handler->handle_repsonse( $download, $response ) on the fetcher response for the download

=back

=cut

sub _spawn_fetchers
{
    my ( $self ) = @_;

    my $in_parent = 1;

    for ( my $i = 0 ; $i < $self->processes ; $i++ )
    {
        my ( $parent_socket, $child_socket ) = IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC );

        LOGDIE "Could not create socket for fetcher $i" unless $parent_socket && $child_socket;

        DEBUG "spawn fetcher $i ...";

        $self->_close_db_connection();

        my $pid = mc_fork();

        if ( $pid )
        {
            TRACE "in parent after spawning fetcher $i";

            $child_socket->close();
            $self->fetchers->[ $i ] = { pid => $pid, socket => $parent_socket };

            TRACE "in parent after spawning fetcher $i db reconnect starting";
            eval { $self->_reconnect_db(); };
            if ( $@ )
            {
                LOGDIE "Error in _reconnect_db() in paranet after spawning fetcher $i";
            }
            TRACE "in parent after spawning fetcher $i db reconnect done";
        }
        else
        {
            TRACE "in child $i";
            $parent_socket->close();
            $in_parent = 0;
            $self->fetcher_number( $i );
            $self->socket( $child_socket );
            $self->_reconnect_db();

            if ( $self->children_exit_on_kill() )
            {
                TRACE "child $i adding sig{ TERM } handler";
                $SIG{ TERM } = \&_exit;
            }
            else
            {
                TRACE "child $i not adding sig{ TERM } handler";
            }

            TRACE "in child $i calling run_fetcher";
            eval { $self->_run_fetcher(); };

            if ( $@ )
            {
                LOGDIE "Error in _run_fetcher for fetcher $i: $@";
            }
        }
    }

    if ( $in_parent )
    {
        ## Give children a catch to initialize to avoid race conditions

        TRACE "Sleeping in parent";
        sleep( 1 );
        TRACE "continuing in parent";

    }
}

=head2 crawl

Start crawling by cralling $self->_spawn_fetchers() and then entering a loop that:

=over

=item *
if the in memory queue of pending downloads is empty, calls $provider->provide_download_ids to refill it;

=item *

listens for a request from a fetcher on the child/parent sockets;

=item *

sends the downloads_id of a pending download to the the requesting fetcher and removes that download from the
in memory queue

=back

=cut

sub crawl
{
    my ( $self ) = @_;

    $self->_spawn_fetchers();

    my $socket_select = IO::Select->new();

    for my $fetcher ( @{ $self->fetchers } )
    {
        $socket_select->add( $fetcher->{ socket } );
    }

    my $provider = MediaWords::Crawler::Provider->new( $self );

    my $start_time = time;

    my $queued_downloads = [];

    DEBUG "starting Crawler::Engine::crawl";

    my $db = $self->dbs;

    MAINLOOP: while ( 1 )
    {
        if ( $self->timeout && ( ( time - $start_time ) > $self->timeout ) )
        {
            TRACE "crawler timed out";
            last MAINLOOP;
        }

        for my $s ( $socket_select->can_read() )
        {
            # set timeout so that a single hung read / write will not hork the whole crawler
            $s->timeout( 60 );

            my $fetcher_number = $s->getline();

            if ( !defined( $fetcher_number ) )
            {
                DEBUG "skipping fetcher for which we couldn't read the fetcher number";
                $socket_select->remove( $s );
                next;
            }

            chomp( $fetcher_number );

            if ( scalar( @{ $queued_downloads } ) == 0 )
            {
                DEBUG "refill queued downloads ...";
                $queued_downloads = $provider->provide_downloads();

                if ( !@{ $queued_downloads } && $self->test_mode )
                {
                    my $wait = 5;
                    INFO "exiting after $wait second wait because crawler is in test mode and queue is empty";
                    sleep $wait;
                    INFO "exiting now.";
                    last MAINLOOP;
                }
            }

            if ( my $queued_download = shift( @{ $queued_downloads } ) )
            {
                if ( !$s->printflush( $queued_download->{ downloads_id } . "\n" ) )
                {
                    # set timeout so that a single hung read / write will not hork the whole crawler
                    $s->timeout( 60 );

                    my $fetcher_number = $s->getline();

                    if ( !defined( $fetcher_number ) )
                    {
                        DEBUG "skipping fetcher for which we couldn't read the fetcher number";
                        $socket_select->remove( $s );
                        next;
                    }

                    chomp( $fetcher_number );

                    if ( scalar( @{ $queued_downloads } ) == 0 )
                    {
                        DEBUG "refill queued downloads ...";
                        $queued_downloads = $provider->provide_download_ids();

                        if ( !@{ $queued_downloads } && $self->test_mode )
                        {
                            my $wait = 5;
                            INFO "exiting after $wait second wait because crawler is in test mode and queue is empty";
                            sleep $wait;
                            INFO "exiting now.";
                            last MAINLOOP;
                        }
                    }

                    if ( my $queued_download = shift( @{ $queued_downloads } ) )
                    {
                        TRACE( "engine sending downloads_id: $queued_download" );
                        if ( !$s->printflush( $queued_download . "\n" ) )
                        {
                            WARN( "provider failed to write download id to fetcher" );
                            unshift( @{ $queued_downloads }, $queued_download );
                        }

                    }
                    else
                    {
                        $s->printflush( "none\n" );
                        last;
                    }
                }

            }
            else
            {
                $s->printflush( "none\n" );
                last;
            }
        }
    }

    kill( 15, map { $_->{ pid } } @{ $self->{ fetchers } } );

    my $wait = 3;
    INFO "waiting $wait seconds for children to exit ...";
    sleep( $wait );

    INFO "using kill 9 to make sure children stop";
    kill( 9, map { $_->{ pid } } @{ $self->{ fetchers } } );
}

=head2 processes

getset processes - the number fetcher processes to spawn.

=cut

sub processes
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ processes } = $_[ 1 ];
    }

    return $_[ 0 ]->{ processes };
}

=head2 sleep_interval

getset sleep_interval - sleep for up to this many seconds each time the provider provides 0 downloads

=cut

sub sleep_interval
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ sleep_interval } = $_[ 1 ];
    }

    return $_[ 0 ]->{ sleep_interval };
}

=head2 throttle

getset throttle - throttle each host to one request every this many secondsm default 10 seconds

=cut

sub throttle
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ throttle } = $_[ 1 ];
    }

    return $_[ 0 ]->{ throttle };
}

=head2 timeout

getset timeout - time for crawler to run before exiting

=cut

sub timeout
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ timeout } = $_[ 1 ];
    }

    return $_[ 0 ]->{ timeout };
}

=head2 pending_check_interval

getset pending_check_interval - interval to check downloads for pending downloads to add to queuem default 600 seconds

=cut

sub pending_check_interval
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ pending_check_interval } = $_[ 1 ];
    }

    return $_[ 0 ]->{ pending_check_interval };
}

=head2 fetcher_number

getset fetcher_number - the index of each spawned fetcher process

=cut

sub fetcher_number
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ fetcher_number } = $_[ 1 ];
    }

    return $_[ 0 ]->{ fetcher_number };
}

=head2 fetchers

getset fetchers - the list of child fetcher processes for root spawning processes

=cut

sub fetchers
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ fetchers } = $_[ 1 ];
    }

    return $_[ 0 ]->{ fetchers };
}

=head2 socket

getset socket - socket to talk to parent process for spawned process

=cut

sub socket
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ socket } = $_[ 1 ];
    }

    return $_[ 0 ]->{ socket };
}

=head2 children_exit_on_kill

getset children_exit_on_kill - whether to kill children process when parent receives a kill signal

=cut

sub children_exit_on_kill
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ children_exit_on_kill } = $_[ 1 ];
    }

    return $_[ 0 ]->{ children_exit_on_kill };
}

=head2 test_mode

getset test_mode - whether the crawler should exit the first time the downloads queue has been emptied rather than
calling $provider->provide_download_ids for more downloads.

if test_mode is set to true, the following other setters are called:

    $self->processes( 1 );
    $self->throttle( 1 );
    $self->sleep_interval( 1 );

=cut

sub test_mode
{
    my ( $self, $test_mode ) = @_;

    if ( defined( $test_mode ) )
    {
        $self->{ test_mode } = $test_mode;

        if ( $test_mode )
        {
            $self->processes( 1 );
            $self->throttle( 1 );
            $self->sleep_interval( 1 );
        }
    }

    return $self->{ test_mode };
}

=head2 dbs

getset dbs - the engine MediaWords::DBI Simple handle

=cut

sub dbs
{
    my ( $self, $dbs ) = @_;

    if ( $dbs )
    {
        LOGDIE( "use $self->_reconnect_db() to connect to db" );
    }

    defined( $self->{ dbs } ) || LOGDIE "no database";

    return $self->{ dbs };
}

sub _close_db_connection
{
    my ( $self ) = @_;

    if ( $self->{ dbs } )
    {
        $self->dbs->disconnect;

        $self->{ dbs } = 0;
    }

    return;
}

=head2 _reconnect_db()

Close the existing $self->dbs and create a new connection.

=cut

sub _reconnect_db
{
    my ( $self ) = @_;

    if ( $self->{ dbs } )
    {
        $self->_close_db_connection();
    }

    $self->{ dbs } = MediaWords::DB::connect_to_db();
}

1;
