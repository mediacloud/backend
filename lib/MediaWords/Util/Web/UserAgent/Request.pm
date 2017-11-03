package MediaWords::Util::Web::UserAgent::Request;

#
# HTTP request
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

{

    package MediaWords::Util::Web::UserAgent::Request::Proxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.util.web.ua.request' );

    1;
}

sub new($$$)
{
    my ( $class, $method, $url ) = @_;

    my $self = {};
    bless $self, $class;

    $self->{ _request } = MediaWords::Util::Web::UserAgent::Request::Proxy::Request->new(
        $method,    #
        $url
    );

    return $self;
}

sub from_python_request($$)
{
    my ( $class, $python_request ) = @_;

    if ( $python_request )
    {
        my $self = {};
        bless $self, $class;

        $self->{ _request } = $python_request;

        return $self;
    }
    else
    {
        return undef;
    }
}

sub python_request()
{
    my ( $self ) = @_;

    return $self->{ _request };
}

sub method($)
{
    my ( $self, $method ) = @_;

    return $self->{ _request }->method();
}

sub set_method($$)
{
    my ( $self, $method ) = @_;

    $self->{ _request }->set_method( $method );
}

sub url($)
{
    my ( $self ) = @_;

    return $self->{ _request }->url();
}

sub set_url($$)
{
    my ( $self, $url ) = @_;

    $self->{ _request }->set_url( $url );
}

sub header($$)
{
    my ( $self, $field ) = @_;

    return $self->{ _request }->header( $field );
}

sub set_header($$$)
{
    my ( $self, $field, $value ) = @_;

    $self->{ _request }->set_header( $field, $value );
}

sub content_type($)
{
    my ( $self ) = @_;

    return $self->{ _request }->content_type();
}

sub set_content_type($$)
{
    my ( $self, $content_type ) = @_;

    $self->{ _request }->set_content_type( $content_type );
}

sub content($)
{
    my ( $self ) = @_;

    return $self->{ _request }->content();
}

sub set_content($$)
{
    my ( $self, $content ) = @_;

    $self->{ _request }->set_content( $content );
}

sub set_content_utf8($$)
{
    my ( $self, $content ) = @_;

    $self->{ _request }->set_content_utf8( $content );
}

sub set_authorization_basic($$$)
{
    my ( $self, $username, $password ) = @_;

    $self->{ _request }->set_authorization_basic( $username, $password );
}

sub as_string($)
{
    my ( $self ) = @_;

    return $self->{ _request }->as_string();
}

1;
