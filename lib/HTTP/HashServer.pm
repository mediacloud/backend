package HTTP::HashServer;

# This is a simple http server that just serves a set of pages defined by a simple hash.  It is intended
# to make it easy to startup a simple server seeded with programmer defined content.
#
# sample hash:
#
# my $pages =  {
#     '/' => 'home',
#     '/foo' => 'foo',
#     '/bar' => { content => '<html>bar</html>', header => 'Content-Type:text/html' }
#     '/foo-bar' => { redirect => '/bar' },
#     '/localhost' => { redirect => "http://localhost:$_port/" },
#     '/127-foo' => { redirect => "http://127.0.0.1:$_port/foo" }
# };
#
# if the value for a page is a string, that string is passed as the content (so 'foo' is transformed into '
# { content => 'foo', header => 'Content-Type: text/plain' }.

use strict;
use warnings;

use English;

use Data::Dumper;
use HTML::Entities;
use HTTP::Server::Simple;
use HTTP::Server::Simple::CGI;
use LWP::Simple;
use Encode;

use base qw(HTTP::Server::Simple::CGI);

# argument for die called by handle_response when a request with the path /die is received
use constant DIE_REQUEST_MESSAGE => 'received /die request';

# create a new server object
sub new
{
    my ( $proto, $port, $pages ) = @_;

    my $class = ref( $proto ) || $proto;

    # send a die request in case there is an existing server sitting around.
    # we have to do this because the signal handling below does not work
    # when run from prove for some reason.
    LWP::Simple::get( "http://localhost:${ port }/die" );

    my $self = $class->SUPER::new( $port );

    bless( $self, $class );

    $self->{ pages } = $pages;
    $self->{ port }  = $port;

    my @paths = keys %{ $pages };
    foreach my $path ( @paths )
    {
        my $page = $pages->{ $path };

        die( "path must start with /: '$path'" ) unless ( $path =~ /^\// );
        if ( $path =~ /.\/$/ )
        {
            my $redirect_path = $path;
            chop( $redirect_path );
            if ( !$pages->{ $redirect_path } )
            {
                $pages->{ $redirect_path } = { redirect => $path };
            }
        }
    }

    return $self;
}

# start the server running in the background.
# setup up signal handler to kill the forked server if this process gets killed.
sub start
{
    my ( $self ) = @_;

    $self->{ pid } = $self->background();

    # sometimes the server takes a brief time to startup
    sleep( 1 );

    $SIG{ INT } = $SIG{ TERM } = sub { kill( 15, $self->{ pid } ); die( "caught ctl-c and killed HTTP::HashServer" ) };
}

sub stop
{
    my ( $self ) = @_;

    say STDERR "Stopping server with PID " . $self->{ pid } . " from PID $$";

    kill( 'KILL', $self->{ pid } );
}

# we have to override this so that we can allow the /die request
# to scape the eval and actually kill the server
sub handler
{
    my ( $self ) = @_;

    eval { $self->handle_request( $self->cgi_class->new ) };

    if ( $@ )
    {
        if ( substr( $@, 0, length( DIE_REQUEST_MESSAGE ) ) eq DIE_REQUEST_MESSAGE )
        {
            die( $@ );
        }
        else
        {
            warn( $@ );
        }
    }
}

# send a response according to the $pages hash passed into new() -- see above for $pages format
sub handle_request
{
    my ( $self, $cgi ) = @_;

    my $path = $cgi->path_info();

    if ( $path eq '/die' )
    {
        $| = 1;
        print <<END;
HTTP/1.0 404 Not found
Content-Type: text/plain

Killing server.
END
        die( DIE_REQUEST_MESSAGE );
    }

    my $page = $self->{ pages }->{ $path };

    if ( !$page )
    {
        print <<END;
HTTP/1.0 404 Not found
Content-Type: text/plain

Not found :(
END
        return;
    }

    $page = { content => $page } unless ( ref( $page ) );

    if ( my $redirect = $page->{ redirect } )
    {
        my $enc_redirect = HTML::Entities::encode_entities( $redirect );
        print <<END
HTTP/1.0 301 Moved Permanently
Content-Type: text/html; charset=UTF-8
Location: $redirect

<html><body>Website was moved to <a href="$enc_redirect">$enc_redirect</a></body></html>
END
    }
    else
    {
        my $header  = $page->{ header }  || 'Content-Type: text/html; charset=UTF-8';
        my $content = $page->{ content } || "<body><html>Filler content for $path</html><body>";
        $content = encode( 'utf-8', $content );

        print <<END;
HTTP/1.0 200 OK
$header

$content
END
    }
}

1;
