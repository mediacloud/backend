package MediaWords::Util::Web::UserAgent;

#
# Class for downloading stuff from the web
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Web::UserAgent::Request;
use MediaWords::Util::Web::UserAgent::Response;
use MediaWords::Util::Config::Common;

{

    package MediaWords::Util::Web::UserAgent::Proxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.util.web.user_agent' );

    1;
}

sub new($;$)
{
    my ( $class, $config ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $config ) {
        $config = MediaWords::Util::Config::Common::user_agent();
    }

    $self->{ _ua } = MediaWords::Util::Web::UserAgent::Proxy::UserAgent->new( $config );

    return $self;
}

sub get($$)
{
    my ( $self, $url ) = @_;

    my $python_response = $self->{ _ua }->get( $url );

    my $response = MediaWords::Util::Web::UserAgent::Response->from_python_response( $python_response );
    return $response;
}

sub get_follow_http_html_redirects($)
{
    my ( $self, $url ) = @_;

    my $python_response = $self->{ _ua }->get_follow_http_html_redirects( $url );

    my $response = MediaWords::Util::Web::UserAgent::Response->from_python_response( $python_response );
    return $response;
}

sub parallel_get($$)
{
    my ( $self, $urls ) = @_;

    my $python_responses = $self->{ _ua }->parallel_get( $urls );
    my $responses        = [];

    foreach my $python_response ( @{ $python_responses } )
    {
        my $response = MediaWords::Util::Web::UserAgent::Response->from_python_response( $python_response );
        push( @{ $responses }, $response );
    }

    return $responses;
}

sub get_string($$)
{
    my ( $self, $url ) = @_;

    return $self->{ _ua }->get_string( $url );
}

sub request($$)
{
    my ( $self, $request ) = @_;

    my $python_request = $request->python_request();

    my $python_response = $self->{ _ua }->request( $python_request );

    my $response = MediaWords::Util::Web::UserAgent::Response->from_python_response( $python_response );
    return $response;
}

sub timing($)
{
    my ( $self ) = @_;

    return $self->{ _ua }->timing();
}

sub set_timing($$)
{
    my ( $self, $timing ) = @_;

    if ( defined $timing )
    {
        if ( ref( $timing ) eq ref( [] ) )
        {
            my $int_timing = [];
            foreach my $t ( @{ $timing } )
            {
                push( @{ $int_timing }, $t + 0 );
            }
            $timing = $int_timing;
        }
    }

    $self->{ _ua }->set_timing( $timing );
}

sub timeout($)
{
    my ( $self ) = @_;

    return $self->{ _ua }->timeout();
}

sub set_timeout($$)
{
    my ( $self, $timeout ) = @_;

    if ( defined $timeout )
    {
        $timeout = $timeout + 0;
    }

    $self->{ _ua }->set_timeout( $timeout );
}

sub max_redirect($)
{
    my ( $self ) = @_;

    return $self->{ _ua }->max_redirect();
}

sub set_max_redirect($$)
{
    my ( $self, $max_redirect ) = @_;

    if ( defined $max_redirect )
    {
        $max_redirect = $max_redirect + 0;
    }

    $self->{ _ua }->set_max_redirect( $max_redirect );
}

sub max_size($)
{
    my ( $self ) = @_;

    return $self->{ _ua }->max_size();
}

sub set_max_size($$)
{
    my ( $self, $max_size ) = @_;

    if ( defined $max_size )
    {
        $max_size = $max_size + 0;
    }

    $self->{ _ua }->set_max_size( $max_size );
}

1;
