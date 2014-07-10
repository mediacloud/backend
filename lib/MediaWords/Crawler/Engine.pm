package MediaWords::Crawler::Engine;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# core engine of crawler:
# * fork specified number of crawlers
# * get Requests from Provider
# * provide Request to each waiting crawlers
#
# * with each crawler
#   * get Request from engine
#   * fetch Request with Fetcher
#   * handle Request with Handler#
#   * repeat

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
use MediaWords::Util::MC_Fork;

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

sub fetch_and_handle_single_download
{

    my ( $self, $download ) = @_;

    $self->reconnect_db();

    my $fetcher = MediaWords::Crawler::Fetcher->new( $self );
    my $handler = MediaWords::Crawler::Handler->new( $self );

    $self->_fetch_and_handle_download( $download, $fetcher, $handler );

    return;
}

# continually loop through the provide, fetch, respond cycle
# for one crawler process
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

# fork off the fetching processes
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

sub _create_fetcher_engine_for_testing
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

# fork off fetching processes and then provide them with requests
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

        while ( 1 )
        {
            if ( $self->timeout && ( ( time - $start_time ) > $self->timeout ) )
            {
                print STDERR "crawler timed out\n";
                last;
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

#TODO merge with the crawl method
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

# fork this many processes
sub processes
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ processes } = $_[ 1 ];
    }

    return $_[ 0 ]->{ processes };
}

# sleep for up to this many seconds each time the provider fails to provide a request
sub sleep_interval
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ sleep_interval } = $_[ 1 ];
    }

    return $_[ 0 ]->{ sleep_interval };
}

# throttle each host to one request every this many seconds
sub throttle
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ throttle } = $_[ 1 ];
    }

    return $_[ 0 ]->{ throttle };
}

# time for crawler to run before exiting
sub timeout
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ timeout } = $_[ 1 ];
    }

    return $_[ 0 ]->{ timeout };
}

# interval to check downloads for pending downloads to add to queue
sub pending_check_interval
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ pending_check_interval } = $_[ 1 ];
    }

    return $_[ 0 ]->{ pending_check_interval };
}

# index of spawned process for spawned process
sub fetcher_number
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ fetcher_number } = $_[ 1 ];
    }

    return $_[ 0 ]->{ fetcher_number };
}

# list of child fetcher processes for root spawning processes
sub fetchers
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ fetchers } = $_[ 1 ];
    }

    return $_[ 0 ]->{ fetchers };
}

# socket to talk to parent process for spawned process
sub socket
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ socket } = $_[ 1 ];
    }

    return $_[ 0 ]->{ socket };
}

sub children_exit_on_kill
{
    if ( defined( $_[ 1 ] ) )
    {
        $_[ 0 ]->{ children_exit_on_kill } = $_[ 1 ];
    }

    return $_[ 0 ]->{ children_exit_on_kill };
}

# engine MediaWords::DBI Simple handle
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
