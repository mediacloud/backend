package MediaWords::Test::LocalServer;

use strict;
use warnings;

use HTTP::Daemon;
use HTTP::Status;

use Data::Dumper;
use File::Temp;

sub _replace_relative_urls_in_file
{
    my ( $base_url, $requested_file_path ) = @_;

    my ( $fh, $modified_file_path ) = File::Temp::tmpnam();

    open( REQUESTED_FILE, "<$requested_file_path" ) || return $requested_file_path;

    while ( <REQUESTED_FILE> )
    {
        my $line = $_;
        $line =~ s/<BASE_WEBSITE_URL\/>/$base_url/;
        print $fh $line;
    }

    close( $fh );
    return $modified_file_path;
}

sub new($$)
{
    my ( $class, $web_directory ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->{ web_directory } = $web_directory;

    return $self;
}

sub DESTROY
{
    my $self = shift;

    if ( $self->{ child_pid } )
    {
        $self->stop();
    }
}

sub start($)
{
    my $self = shift;

    $self->{ daemon } = HTTP::Daemon->new( ReuseAddr => 1 ) or die "Unable to start HTTP::Daemon: $!";

    say STDERR "Daemon <URL: " . $self->{ daemon }->url . ">";

    my $pid = fork();
    if ( $pid != 0 )
    {
        say STDERR "Forked child process $pid, returning";
        $self->{ child_pid } = $pid;

        # parent
        return;
    }

    while ( my $c = $self->{ daemon }->accept )
    {

        while ( my $r = $c->get_request )
        {
            my $uri = $r->uri;

            # We use "as_string" because URL paths with two slashes (e.g.
            # "//gv/test.rss") could be interpreted as "http://gv/test.rss" by
            # the URI module
            my $path = $uri->as_string;
            say STDERR "URI path is '$path'";

            if ( $r->method eq 'GET' && $path && $path !~ /\.\./ )
            {

                #change double slash to single slash
                $path =~ s/^\/\//\//;

                say STDERR "Normalized path is '$path'";
                if ( $path eq '/kill_server' )
                {
                    $c->send_response( "shutting down" );
                    $c->close;
                    undef( $c );
                    say STDERR "Shutting down server";
                    exit;
                }

                $path = $self->{ web_directory } . "/$path";

                if ( $path =~ /\.rss$/ )
                {
                    $path = _replace_relative_urls_in_file( $self->url(), $path );
                }

                unless ( -f $path )
                {
                    die "File at path $path does not exist.";
                }

                say STDERR "Sending file $path...";
                $c->send_file_response( $path ) or die "Unable to send file $path: ''$!' $@' '$?'";
                say STDERR "Sent file $path";
            }
            else
            {
                say STDERR "Won't serve path: " . $r->uri->path;
                say STDERR "Request: " . Dumper( $r );
                $c->send_error( RC_FORBIDDEN );
            }
        }
        say STDERR "closing connection";
        $c->close;
        undef( $c );
    }
}

sub stop($)
{
    my $self = shift;

    unless ( $self->{ daemon } )
    {
        warn "HTTP server is not started.";
        return;
    }

    unless ( $self->{ child_pid } )
    {
        die "HTTP server must be started, but the child PID is empty.";
    }

    # say STDERR "Killing " . $self->{ child_pid };
    kill 9, $self->{ child_pid };

    delete $self->{ child_pid };
    delete $self->{ daemon };
}

sub url($)
{
    my $self = shift;

    unless ( $self->{ daemon } )
    {
        die "Daemon is undef; run start()";
    }

    return $self->{ daemon }->url;
}

1;
