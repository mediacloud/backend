package MediaWords::Util::Web::UserAgent::Request;

#
# HTTP request
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use URI::Escape;

{

    package MediaWords::Util::Web::UserAgent::Request::Proxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.util.web.user_agent.request.request' );

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

    # All strings in Python are Unicode already, so we'll need to do this
    # encoding step only for Perl
    if ( ref( $content ) eq ref( {} ) )
    {

        my $post_items = [];
        for my $key ( keys( %{ $content } ) )
        {
            my $enc_key = $key;
            if ( Encode::is_utf8( $enc_key ) ) {
                $enc_key = encode_utf8( $enc_key );
            }

            $enc_key = uri_escape( $enc_key );

            my $data    = $content->{ $key };
            next unless ( $data );
            $data = [ $data ] unless ( ref( $data ) eq ref( [] ) );
            for my $datum ( @{ $data } )
            {
                my $enc_datum = $datum;
                if ( Encode::is_utf8( $enc_datum ) ) {
                    $enc_datum = encode_utf8( $enc_datum );
                }

                $enc_datum = uri_escape( $enc_datum );

                push( @{ $post_items }, "$enc_key=$enc_datum" );
            }
        }

        $content = join( '&', @{ $post_items } );
    }
    else
    {
        if ( Encode::is_utf8( $content ) ) {
            $content = encode_utf8( $content );
        }

    }

    $self->{ _request }->set_content( $content );
}

sub set_authorization_basic($$$)
{
    my ( $self, $username, $password ) = @_;

    $self->{ _request }->set_authorization_basic( $username, $password );
}

1;
