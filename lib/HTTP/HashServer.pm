package HTTP::HashServer;

# this module uses

use strict;

use Data::Dumper;
use HTML::Entities;
use HTTP::Server::Simple;
use HTTP::Server::Simple::CGI;

use base qw(HTTP::Server::Simple::CGI);

# create a new server object
sub new
{
    my ( $proto, $port, $pages ) = @_;

    my $class = ref( $proto ) || $proto;

    my $self = $class->SUPER::new( $port );

    bless( $self, $class );

    $self->{ pages } = $pages;

    while ( my ( $path, $page ) = each( %{ $pages } ) )
    {
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

    $SIG{ CHLD } = 'IGNORE';
    $SIG{ INT } = $SIG{ TERM } = sub { kill( 15, $self->{ pid } ) };
}

sub stop
{
    my ( $self ) = @_;

    kill( 15, $self->{ pid } );
}

sub handle_request
{
    my ( $self, $cgi ) = @_;

    my $path = $cgi->path_info();

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
        print <<END;
HTTP/1.0 200 OK
$header

$content
END
    }
}

1;
