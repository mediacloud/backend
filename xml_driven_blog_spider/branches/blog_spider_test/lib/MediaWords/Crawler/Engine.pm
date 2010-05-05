package MediaWords::Crawler::Engine;

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

use Fcntl;
use IO::Select;
use IO::Socket;

use MediaWords::Crawler::Fetcher;
use MediaWords::Crawler::Handler;
use MediaWords::Crawler::Provider;
use DBIx::Simple::MediaWords;

sub new
{
    my ($class) = @_;

    my $self = {};
    bless( $self, $class );

    $self->processes(1);
    $self->sleep_interval(60);
    $self->throttle(30);
    $self->fetchers( [] );
    $self->dbs( DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info) );

    return $self;
}

# continually loop through the provide, fetch, respond cycle
# for one crawler process
sub _run_fetcher
{
    my ($self) = @_;

    print STDERR "fetcher " . $self->fetcher_number . " crawl loop\n";

    $self->dbs( DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info) );

    my $fetcher = MediaWords::Crawler::Fetcher->new($self);
    my $handler = MediaWords::Crawler::Handler->new($self);

    my $download;

    while (1)
    {
        my $download;
        eval {

            $self->dbs( DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info) );

            # tell the parent provider we're ready for another download
            # and then read the download id from the socket
            $self->socket->print( $self->fetcher_number() . "\n" );
            my $downloads_id = $self->socket->getline();
            if ( defined($downloads_id) )
            {
                chomp($downloads_id);
            }

            if ( !$downloads_id || ( $downloads_id eq 'none' ) )
            {
                next;
            }

            #print "fetcher " . $self->fetcher_number . " get downloads_id: '$downloads_id'\n";

            $download = $self->dbs->find_by_id( 'downloads', $downloads_id );
            if ( !$download )
            {
                die("Unable to find download_id: $downloads_id");
            }

            my $response = $fetcher->fetch_download($download);
            $handler->handle_response( $download, $response );

            print STDERR "fetcher " . $self->fetcher_number . " " . $download->{url} . " complete\n";
        };

        if ($@)
        {
            print STDERR "ERROR: fetcher " . $self->fetcher_number . ":\n****\n$@\n****\n";
            if ( $download && ( !grep { $_ eq $download->{state} } ( 'fetching', 'queued' ) ) )
            {
                $download->{state}         = 'error';
                $download->{error_message} = $@;
                $self->dbs->update_by_id( 'downloads', $download->{downloads_id}, $download );
            }

        }
    }
}

# fork off the fetching processes
sub spawn_fetchers
{
    my ($self) = @_;

    for ( my $i = 0 ; $i < $self->processes ; $i++ )
    {

        #sharing dbs handles between processes doesn't work well so get rid of the current dbs handle before we fork
        $self->close_and_undefine_dbs();

        my ( $parent_socket, $child_socket ) = IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC );

        print STDERR "spawn fetcher $i ...\n";
        my $pid = fork();

        if ($pid)
        {
            $child_socket->close();
            $self->fetchers->[$i] = { pid => $pid, socket => $parent_socket };
            $self->dbs( DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info) );
        }
        else
        {
            $parent_socket->close();
            $self->fetcher_number($i);
            $self->socket($child_socket);
            $self->dbs( DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info) );
            $self->_run_fetcher();
        }
    }
}

# fork off fetching processes and then provide then with requests
sub crawl
{
    my ($self) = @_;

    $self->spawn_fetchers();

    my $socket_select = IO::Select->new();

    for my $fetcher ( @{ $self->fetchers } )
    {
        $socket_select->add( $fetcher->{socket} );
    }

    my $provider = MediaWords::Crawler::Provider->new($self);

    my $start_time = time;

    my $queued_downloads = [];
    while (1)
    {
        if ( $self->timeout && ( ( time - $start_time ) > $self->timeout ) )
        {
            print STDERR "crawler timed out\n";
            last;
        }

        if ( scalar( @{$queued_downloads} ) == 0 )
        {
            print STDERR "refill queued downloads ...\n";
            $queued_downloads = $provider->provide_downloads();
        }

        #print "wait for fetcher requests ...\n";
        for my $s ( $socket_select->can_read() )
        {
            my $fetcher_number = $s->getline();
            chomp($fetcher_number);

            #print "get fetcher $fetcher_number ping\n";

            #print "sending fetcher $fetcher_number download\n";
            if ( my $queued_download = shift( @{$queued_downloads} ) )
            {
                $s->print( $queued_download->{downloads_id} . "\n" );
            }
            else
            {
                $s->print("none\n");
            }

            #print "fetcher $fetcher_number request assigned\n";
        }
    }

    kill( 15, map { $_->{pid} } @{ $self->{fetchers} } );
    print "waiting 5 seconds for children to exit ...\n";
    sleep(5);
}

# fork this many processes
sub processes
{
    if ( defined( $_[1] ) )
    {
        $_[0]->{processes} = $_[1];
    }

    return $_[0]->{processes};
}

# sleep for up to this many seconds each time the provider fails to provide a request
sub sleep_interval
{
    if ( defined( $_[1] ) )
    {
        $_[0]->{sleep_interval} = $_[1];
    }

    return $_[0]->{sleep_interval};
}

# throttle each host to one request every this many seconds
sub throttle
{
    if ( defined( $_[1] ) )
    {
        $_[0]->{throttle} = $_[1];
    }

    return $_[0]->{throttle};
}

# time for crawler to run before exiting
sub timeout
{
    if ( defined( $_[1] ) )
    {
        $_[0]->{timeout} = $_[1];
    }

    return $_[0]->{timeout};
}

# interval to check downloads for pending downloads to add to queue
sub pending_check_interval
{
    if ( defined( $_[1] ) )
    {
        $_[0]->{pending_check_interval} = $_[1];
    }

    return $_[0]->{pending_check_interval};
}

# index of spawned process for spawned process
sub fetcher_number
{
    if ( defined( $_[1] ) )
    {
        $_[0]->{fetcher_number} = $_[1];
    }

    return $_[0]->{fetcher_number};
}

# list of child fetcher processes for root spawning processes
sub fetchers
{
    if ( defined( $_[1] ) )
    {
        $_[0]->{fetchers} = $_[1];
    }

    return $_[0]->{fetchers};
}

# socket to talk to parent process for spawned process
sub socket
{
    if ( defined( $_[1] ) )
    {
        $_[0]->{socket} = $_[1];
    }

    return $_[0]->{socket};
}

# engine MediaWords::DBI Simple handle
sub dbs
{

    #TODO can't get DBIx::Simple to play nice with multiple forked processes...

    # $_[0]->{dbs} = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);

    if ( defined( $_[1] ) )
    {
        $_[0]->{dbs} = $_[1];

        defined( $_[0]->{dbs} ) || die "error opening database connection $@";
        if ( !( $_[0]->{dbs}->{sucess} ) && ( $_[0]->{dbs}->{reason} ) )
        {
            die $_[0]->{dbs}->{reason};
        }
    }

    defined( $_[0]->{dbs} ) || die "error opening database connection $@";

    return $_[0]->{dbs};
}

sub close_and_undefine_dbs
{
    my ($self) = @_;
    $self->dbs->commit;
    $self->dbs->disconnect;
    undef( $self->{dbs} );
}

1;
