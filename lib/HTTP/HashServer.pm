package HTTP::HashServer;

# This is a simple http server that just serves a set of pages defined by a simple hash.  It is intended
# to make it easy to startup a simple server seeded with programmer defined content.
#
# sample hash:
#
# my $pages =  {
#     '/' => 'home',
#     '/foo' => 'foo',
#     '/bar' => { content => '<html>bar</html>', header => 'Content-Type: text/html' }
#     '/foo-bar' => { redirect => '/bar' },
#     '/localhost' => { redirect => "http://localhost:$_port/" },
#     '/127-foo' => { redirect => "http://127.0.0.1:$_port/foo", http_status_code => 303 },
#     '/callback' => sub {
#         my ( $self, $cgi ) = @_;
#         print "HTTP/1.0 200 OK\r\n";
#         print "Content-Type: text/plain\r\n";
#         print "\r\n";
#         print "This is callback.";
#     },
#     '/auth' => { auth => 'user:password' }
# };
#
# if the value for a page is a string, that string is passed as the content (so 'foo' is transformed into '
# { content => 'foo', header => 'Content-Type: text/plain' }.

use strict;
use warnings;

use English;

use Data::Dumper;
use Encode;
use HTML::Entities;
use HTTP::Server::Simple;
use HTTP::Server::Simple::CGI;
use HTTP::Status;
use LWP::Simple;
use MIME::Base64;
use Readonly;

use base qw(HTTP::Server::Simple::CGI);

# argument for die called by handle_response when a request with the path /die is received
Readonly my $DIE_REQUEST_MESSAGE => 'received /die request';

# Default HTTP status code for redirects ("301 Moved Permanently")
Readonly my $DEFAULT_REDIRECT_STATUS_CODE => 301;

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

        # redirect foo to foo/ unless foo/ already has a page
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

    # say STDERR "Stopping server with PID " . $self->{ pid } . " from PID $$";

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
        if ( substr( $@, 0, length( $DIE_REQUEST_MESSAGE ) ) eq $DIE_REQUEST_MESSAGE )
        {
            die( $@ );
        }
        else
        {
            warn( $@ );
        }
    }
}

# setup $self->{ headers } with the headers for the current request
sub header
{
    my ( $self, $name, $val ) = @_;

    $self->{ headers }->{ $name } = $val;

    # Process HTTP headers with parent package (HTTP::Server::Simple::CGI) too
    $self->SUPER::header( $name, $val );
}

# if auth is required for this page and the auth was not supplied by the request,
# print a 401 page and return 1; otherwise return 0.
sub request_failed_authentication
{
    my ( $self, $page ) = @_;

    my $page_auth = $page->{ auth } || return 0;

    my $fail_authentication_page = '';
    $fail_authentication_page .= "HTTP/1.1 401 Access Denied\r\n";
    $fail_authentication_page .= "WWW-Authenticate: Basic realm=\"HashServer\"\r\n";
    $fail_authentication_page .= "Content-Length: 0\r\n";

    my $client_auth = $self->{ headers }->{ Authorization };

    if ( !$client_auth )
    {
        print $fail_authentication_page;
        return 1;
    }

    if ( !( $client_auth =~ /Basic (.*)$/ ) )
    {
        say STDERR "unable to parse Authorization header: $client_auth";
        print $fail_authentication_page;
        return 1;
    }

    my $encoded = $1;

    my $userpass = decode_base64( $encoded );

    if ( !( $userpass eq $page_auth ) )
    {
        print $fail_authentication_page;
        return 1;
    }

    return 0;
}

# send a response according to the $pages hash passed into new() -- see above for $pages format
sub handle_request
{
    my ( $self, $cgi ) = @_;

    my $path = $cgi->path_info();

    if ( $path eq '/die' )
    {
        $| = 1;
        print "HTTP/1.0 404 Not found\r\n";
        print "Content-Type: text/plain\r\n";
        print "\r\n";
        print "Killing server.";

        die( $DIE_REQUEST_MESSAGE );
    }

    my $page = $self->{ pages }->{ $path };

    if ( !$page )
    {
        print "HTTP/1.0 404 Not found\r\n";
        print "Content-Type: text/plain\r\n";
        print "\r\n";
        print "Not found :(";
        return;
    }

    $page = { content => $page } unless ( ref( $page ) );

    return 0 if ( request_failed_authentication( $self, $page ) );

    if ( my $redirect = $page->{ redirect } )
    {
        my $enc_redirect = HTML::Entities::encode_entities( $redirect );

        my $http_status_code = $page->{ http_status_code } // $DEFAULT_REDIRECT_STATUS_CODE;
        my $http_status_message = HTTP::Status::status_message( $http_status_code )
          || die( "unknown status code '$http_status_code'" );

        print "HTTP/1.0 $http_status_code $http_status_message\r\n";
        print "Content-Type: text/html; charset=UTF-8\r\n";
        print "Location: $redirect\r\n";
        print "\r\n";
        print '<html><body>Website was moved to <a href="' . $enc_redirect . '">' . $enc_redirect . '</a></body></html>';
    }
    elsif ( my $callback = $page->{ callback } )
    {
        if ( ref $callback ne 'CODE' )
        {
            die "'callback' parameter exists but is not a subroutine reference.";
        }
        $callback->( $self, $cgi );
    }
    else
    {
        my $header  = $page->{ header }  || 'Content-Type: text/html; charset=UTF-8';
        my $content = $page->{ content } || "<body><html>Filler content for $path</html><body>";

        my $http_status_code = $page->{ http_status_code } // 200;
        my $http_status_message = HTTP::Status::status_message( $http_status_code )
          || die( "unknown status code '$http_status_code'" );

        if ( $header =~ /\n/ and $header !~ /\r/ )
        {
            $header =~ s/\n/\r\n/gs;
        }
        $content = encode( 'utf-8', $content );

        print "HTTP/1.0 $http_status_code $http_status_message\r\n";
        print "$header\r\n";
        print "\r\n";
        print "$content";
    }
}

1;
