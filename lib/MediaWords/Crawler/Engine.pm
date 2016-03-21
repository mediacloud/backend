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

    if ( !$download )
    {
        die( "fetcher " . $self->fetcher_number . ": Unable to find download_id: $download->{downloads_id}" );
    }

    say STDERR "fetcher " .
      $self->fetcher_number . " get downloads_id: '$download->{downloads_id}' " . $download->{ url } . " starting";

    my $start_fetch_time = [ Time::HiRes::gettimeofday ];
    my $response         = $fetcher->fetch_download( $download );
    my $end_fetch_time   = [ Time::HiRes::gettimeofday ];

    say STDERR "fetcher " .
      $self->fetcher_number . " get downloads_id: '$download->{downloads_id}' " . $download->{ url } . " fetched";

    $DB::single = 1;
    eval { $handler->handle_response( $download, $response ); };

    my $fetch_time = Time::HiRes::tv_interval( $start_fetch_time, $end_fetch_time );
    my $handle_time = Time::HiRes::tv_interval( $end_fetch_time );

    if ( $@ )
    {
        die( "Error in handle_response() for downloads_id '$download->{downloads_id}' '" . $download->{ url } . "' : $@" );
    }

    print STDERR "fetcher " . $self->fetcher_number . " get downloads_id: '$download->{downloads_id}' " .
      $download->{ url } . " processing complete [ $fetch_time / $handle_time ]\n";

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

    print STDERR "fetcher " . $self->fetcher_number . " crawl loop\n";

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

                # print STDERR "fetcher " . $self->fetcher_number . " get downloads_id: '$downloads_id'\n";
                $download = $self->dbs->find_by_id( 'downloads', $downloads_id );

                $self->_fetch_and_handle_download( $download, $fetcher, $handler );

            }
            elsif ( $downloads_id && ( $downloads_id eq 'exit' ) )
            {
                #say STDERR "exiting as a fetcher";

                #exit 0;
            }
            else
            {

                # $downloads_id = ( !defined( $downloads_id ) ) ? 'undef' : $downloads_id;
                # print STDERR "fetcher undefined downloads_id\n";
                sleep( 3 );
            }
        };

        if ( $@ )
        {
            print STDERR "ERROR: fetcher " . $self->fetcher_number . ":\n****\n$@\n****\n";
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

        die "Could not create socket for fetcher $i" unless $parent_socket && $child_socket;

        print STDERR "spawn fetcher $i ...\n";

        $self->_close_db_connection();

        my $pid = mc_fork();

        if ( $pid )
        {
            say STDERR "in parent after spawning fetcher $i";
            $child_socket->close();
            $self->fetchers->[ $i ] = { pid => $pid, socket => $parent_socket };
            say STDERR "in parent after spawning fetcher $i db reconnect starting";
            eval { $self->reconnect_db; };
            if ( $@ )
            {
                die "Error in reconnect_db in paranet after spawning fetcher $i";
            }
            say STDERR "in parent after spawning fetcher $i db reconnect done";
        }
        else
        {
            say STDERR "in child $i ";
            $parent_socket->close();
            $in_parent = 0;
            $self->fetcher_number( $i );
            $self->socket( $child_socket );
            $self->reconnect_db;

            if ( $self->children_exit_on_kill() )
            {
                say STDERR "child $i adding sig{ TERM } handler";
                $SIG{ TERM } = \&_exit;
            }
            else
            {
                say STDERR "child $i not adding sig{ TERM } handler";
            }

            say STDERR "in child $i calling run_fetcher";
            eval { $self->_run_fetcher(); };

            if ( $@ )
            {
                die "Error in _run_fetcher for fetcher $i: $@";
            }
        }
    }

    if ( $in_parent )
    {
        ## Give children a catch to initialize to avoid race conditions

        say STDERR "Sleeping in parent";
        sleep( 1 );
        say STDERR "continuing in parent";

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

    say STDERR "starting Crawler::Engine::crawl";

    MediaWords::DB::run_block_with_large_work_mem
    {

      MAINLOOP: while ( 1 )
        {
            if ( $self->timeout && ( ( time - $start_time ) > $self->timeout ) )
            {
                print STDERR "crawler timed out\n";
                last MAINLOOP;
            }

            #print "wait for fetcher requests ...\n";
            for my $s ( $socket_select->can_read() )
            {
                my $fetcher_number = $s->getline();

                if ( !defined( $fetcher_number ) )
                {
                    print STDERR "skipping fetcher in which we couldn't read the fetcher number\n";
                    $socket_select->remove( $s );
                    next;
                }

                chomp( $fetcher_number );

                #print "get fetcher $fetcher_number ping\n";

                if ( scalar( @{ $queued_downloads } ) == 0 )
                {
                    print STDERR "refill queued downloads ...\n";
                    $queued_downloads = $provider->provide_downloads();

                    if ( !@{ $queued_downloads } && $self->test_mode )
                    {
                        print STDERR "exiting after 30 second wait because crawler is in test mode and queue is empty\n";
                        sleep 30;
                        print STDERR "exiting now.\n";
                        last MAINLOOP;
                    }
                }

                if ( my $queued_download = shift( @{ $queued_downloads } ) )
                {

                    # print STDERR "sending fetcher $fetcher_number download:" . $queued_download->{downloads_id} . "\n";
                    $s->printflush( $queued_download->{ downloads_id } . "\n" );
                }
                else
                {

                    #print STDERR "sending fetcher $fetcher_number none\n";
                    $s->printflush( "none\n" );
                    last;
                }

                # print "fetcher $fetcher_number request assigned\n";
            }

        }

    }

    $self->dbs;

    kill( 15, map { $_->{ pid } } @{ $self->{ fetchers } } );
    print STDERR "waiting 5 seconds for children to exit ...\n";
    sleep( 5 );

    print STDERR "using kill 9 to make sure children stop ";
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

    #print "wait for fetcher requests ...\n";

    $self->dbs->begin;

  OUTER_LOOP:
    while ( 1 )
    {
        for my $s ( $socket_select->can_read() )
        {
            my $fetcher_number = $s->getline();

            if ( !defined( $fetcher_number ) )
            {
                print STDERR "skipping fetcher in which we couldn't read the fetcher number\n";
                $socket_select->remove( $s );
                next;
            }

            chomp( $fetcher_number );

            #print "get fetcher $fetcher_number ping\n";

            if ( my $queued_download = shift( @{ $queued_downloads } ) )
            {

                # print STDERR "sending fetcher $fetcher_number download:" . $queued_download->{downloads_id} . "\n";
                $s->printflush( $queued_download->{ downloads_id } . "\n" );
            }
            else
            {

                #print STDERR "sending fetcher $fetcher_number none\n";
                $s->printflush( "exit\n" );

                my @fetchers = @{ $self->{ fetchers } };

                my $fetcher = $fetchers[ $fetcher_number ];

                my $fetcher_pid = $fetcher->{ pid };

                sleep( 3 );
                say STDERR "waiting for fetcher $fetcher_number ( pid  $fetcher_pid ) ";

                #waitpid ( $fetcher_pid, 0 );

                say STDERR "exiting loop after wait";
                last OUTER_LOOP;
            }

            # print "fetcher $fetcher_number request assigned\n";

            #last OUTER_LOOP;
        }

    }
    $self->dbs->commit;

    sleep( 5 );

    #kill( 15, map { $_->{ pid } } @{ $self->{ fetchers } } );
    print "waiting 5 seconds for children to exit ...\n";
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
        die( "use $self->reconnect_db to connect to db" );
    }

    defined( $self->{ dbs } ) || die "no database";

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
