package MediaWords::Crawler::Engine;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::Crawler::Engine - controls and coordinates the work of the crawler provider, fetchers, and handlers

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
use Time::HiRes;

use MediaWords::Crawler::Fetcher;
use MediaWords::Crawler::Handler;
use MediaWords::Crawler::Provider;
use MediaWords::Util::Process;

=head1 METHODS

=head2 new

Create new crawler engine object.

=cut

sub new
{
    my ( $class ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->processes( 1 );
    $self->sleep_interval( 60 );
    $self->throttle( 30 );
    $self->fetchers( [] );
    $self->reconnect_db();
    $self->children_exit_on_kill( 0 );
    $self->test_mode( 0 );

    return $self;
}

sub _fetch_and_handle_download
{

    my ( $self, $download, $fetcher, $handler ) = @_;

    my $url = $download->{ url };

    if ( !$download )
    {
        LOGDIE( "fetch " . $self->fetcher_number . ": Unable to find download_id: $download->{downloads_id}" );
    }

    DEBUG( sub { "fetch " . $self->fetcher_number . ": $download->{downloads_id} $url ..." } );

    my $start_fetch_time = [ Time::HiRes::gettimeofday ];
    my $response         = $fetcher->fetch_download( $download );
    my $end_fetch_time   = [ Time::HiRes::gettimeofday ];

    $DB::single = 1;
    eval { $handler->handle_response( $download, $response ); };

    my $fetch_time = Time::HiRes::tv_interval( $start_fetch_time, $end_fetch_time );
    my $handle_time = Time::HiRes::tv_interval( $end_fetch_time );

    if ( $@ )
    {
        LOGDIE( "Error in handle_response() for downloads_id $download->{downloads_id} $url : $@" );
    }

    DEBUG( sub { "fetch " . $self->fetcher_number . ": $download->{downloads_id} $url done [$fetch_time/$handle_time]" } );

    return;
}

=head2 fetch_and_handle_single_download

Fetch and handle only a single download.  Useful mostly for testing.

=cut

sub fetch_and_handle_single_download
{

    my ( $self, $download ) = @_;

    $self->reconnect_db();

    my $fetcher = MediaWords::Crawler::Fetcher->new( $self );
    my $handler = MediaWords::Crawler::Handler->new( $self );

    $self->_fetch_and_handle_download( $download, $fetcher, $handler );

    return;
}

# continually loop through the provide, fetch, respond cycle for one crawler process
sub _run_fetcher
{
    my ( $self ) = @_;

    DEBUG( sub { "fetch " . $self->fetcher_number . " crawl loop" } );

    $self->reconnect_db();

    my $fetcher = MediaWords::Crawler::Fetcher->new( $self );
    my $handler = MediaWords::Crawler::Handler->new( $self );

    my $download;

    $self->socket->blocking( 0 );

    while ( 1 )
    {
        my $download;
        eval {

            $download = 0;

            $self->reconnect_db;

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
                $download = $self->dbs->find_by_id( 'downloads', $downloads_id );

                $self->_fetch_and_handle_download( $download, $fetcher, $handler );
            }
            elsif ( $downloads_id && ( $downloads_id eq 'exit' ) )
            {
            }
            else
            {
                sleep( 3 );
            }
        };

        if ( $@ )
        {
            WARN( sub { "ERROR: fetcher " . $self->fetcher_number . ":\n****\n$@\n****" } );
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

=head2 spawn_fetchers

Fork off $self->process number of fetching processes.  For each forked fetching process, create socket between the
parent and child process.  In each child process, take care to reconnect to db and then enter an infinite
fetch/handle loop that:

=over

=item *

requests a new download id from the engine parent process via the parent/child socket;

=item *

calls $fetcher->fetch_download to get an http response for a download;

=item *

calls $handler->handle_repsonse( $download, $response ) on the fetcher response for the download

=back

=cut

sub spawn_fetchers
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
            eval { $self->reconnect_db; };
            if ( $@ )
            {
                LOGDIE "Error in reconnect_db in paranet after spawning fetcher $i";
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
            $self->reconnect_db;

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

=head2 create_fetcher_engine_for_testing

create a simple engine that consists of only a single fetcher process that can be manually passed a download to
test the fetcher / handle process.

=cut

sub create_fetcher_engine_for_testing
{
    my ( $fetcher_number ) = @_;

    my $crawler = MediaWords::Crawler::Engine->new();

    #$crawler->processes( 1 );
    #$crawler->throttle( 1 );
    #$crawler->sleep_interval( 1 );

    #$crawler->timeout( $crawler_timeout );
    #$crawler->pending_check_interval( 1 );

    $crawler->fetcher_number( $fetcher_number );

    return $crawler;
}

=head2 crawl

Start crawling by cralling $self->spawn_fetchers and then entering a loop that:

=over

=item *
if the in memory queue of pending downloads is empty, calls $provider->provide_downloads to refill it;

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

    $self->spawn_fetchers();

    my $socket_select = IO::Select->new();

    for my $fetcher ( @{ $self->fetchers } )
    {
        $socket_select->add( $fetcher->{ socket } );
    }

    my $provider = MediaWords::Crawler::Provider->new( $self );

    my $start_time = time;

    my $queued_downloads = [];

    DEBUG "starting Crawler::Engine::crawl";

    MediaWords::DB::run_block_with_large_work_mem
    {

      MAINLOOP: while ( 1 )
        {
            if ( $self->timeout && ( ( time - $start_time ) > $self->timeout ) )
            {
                TRACE "crawler timed out";
                last MAINLOOP;
            }

            for my $s ( $socket_select->can_read() )
            {
                my $fetcher_number = $s->getline();

                if ( !defined( $fetcher_number ) )
                {
                    DEBUG "skipping fetcher in which we couldn't read the fetcher number";
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
                        INFO "exiting after 30 second wait because crawler is in test mode and queue is empty";
                        sleep 30;
                        INFO "exiting now.\n";
                        last MAINLOOP;
                    }
                }

                if ( my $queued_download = shift( @{ $queued_downloads } ) )
                {
                    $s->printflush( $queued_download->{ downloads_id } . "\n" );
                }
                else
                {
                    $s->printflush( "none\n" );
                    last;
                }
            }
        }
    }

    $self->dbs;

    kill( 15, map { $_->{ pid } } @{ $self->{ fetchers } } );
    INFO "waiting 5 seconds for children to exit ...";
    sleep( 5 );

    INFO "using kill 9 to make sure children stop";
    kill( 9, map { $_->{ pid } } @{ $self->{ fetchers } } );
}

=head2 crawl_single_download

Enter the crawl loop but crawl only a single download.  Used for testing in place of crawl().

=cut

sub crawl_single_download
{
    my ( $self, $downloads_id ) = @_;

    $self->spawn_fetchers();

    my $socket_select = IO::Select->new();

    for my $fetcher ( @{ $self->fetchers } )
    {
        $socket_select->add( $fetcher->{ socket } );
    }

    my $start_time = time;

    my $download = $self->dbs->find_by_id( 'downloads', $downloads_id );
    my $queued_downloads = [ $download ];

    $self->dbs->begin;

  OUTER_LOOP:
    while ( 1 )
    {
        for my $s ( $socket_select->can_read() )
        {
            my $fetcher_number = $s->getline();

            if ( !defined( $fetcher_number ) )
            {
                DEBUG "skipping fetcher in which we couldn't read the fetcher number";
                $socket_select->remove( $s );
                next;
            }

            chomp( $fetcher_number );

            if ( my $queued_download = shift( @{ $queued_downloads } ) )
            {
                $s->printflush( $queued_download->{ downloads_id } . "\n" );
            }
            else
            {
                $s->printflush( "exit\n" );

                my @fetchers = @{ $self->{ fetchers } };

                my $fetcher = $fetchers[ $fetcher_number ];

                my $fetcher_pid = $fetcher->{ pid };

                sleep( 3 );
                DEBUG "waiting for fetcher $fetcher_number ( pid  $fetcher_pid ) ";

                DEBUG "exiting loop after wait";
                last OUTER_LOOP;
            }
        }

    }
    $self->dbs->commit;

    sleep( 5 );

    INFO "waiting 5 seconds for children to exit ...";
    sleep( 5 );
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
calling $provider->provide_downloads for more downloads.

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
        LOGDIE( "use $self->reconnect_db to connect to db" );
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

=head2 reconnect_db

Close the existing $self->dbs and create a new connection.

=cut

sub reconnect_db
{
    my ( $self ) = @_;

    if ( $self->{ dbs } )
    {
        $self->_close_db_connection();
    }

    $self->{ dbs } = MediaWords::DB::connect_to_db;
    $self->dbs->dbh->{ AutoCommit } = 1;
}

1;
