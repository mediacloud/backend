package MediaWords::Util::Web::UserAgent::Request;

#
# Wrapper around HTTP::Request
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use Encode;
use HTTP::Request;
use URI::Escape;

sub new($$$)
{
    my ( $class, $method, $uri ) = @_;

    my $self = {};
    bless $self, $class;

    if ( $uri )
    {
        if ( ref( $uri ) eq 'URI' )
        {
            LOGCONFESS "Please pass URL as string, not as URI object.";
        }
    }

    $self->{ _request } = HTTP::Request->new( $method, $uri );

    return $self;
}

# Used internally to wrap HTTP::Request into this class
sub new_from_http_request($$)
{
    my ( $class, $request ) = @_;

    unless ( ref( $request ) eq 'HTTP::Request' )
    {
        LOGCONFESS "Response is not HTTP::Request: " . Dumper( $request );
    }

    my $self = {};
    bless $self, $class;

    $self->{ _request } = $request;

    return $self;
}

# Used internally to return underlying HTTP::Request object
sub http_request($)
{
    my ( $self ) = @_;
    return $self->{ _request };
}

# method() getter
sub method($)
{
    my ( $self, $method ) = @_;
    return $self->{ _request }->method();
}

# method() setter
sub set_method($$)
{
    my ( $self, $method ) = @_;
    $self->{ _request }->method( $method );
}

# uri() is not aliased because it returns URI object which we won't reimplement in Web.pm

# url() getter
sub url($)
{
    my ( $self ) = @_;

    my $uri = $self->{ _request }->uri();
    if ( defined $uri )
    {
        return $uri->as_string;
    }
    else
    {
        return undef;
    }
}

# url() setter
sub set_url($$)
{
    my ( $self, $url ) = @_;

    my $uri = URI->new( $url );
    $self->{ _request }->uri( $uri );
}

# header() getter
sub header($$)
{
    my ( $self, $field ) = @_;
    return $self->{ _request }->header( $field );
}

# header() setter
sub set_header($$$)
{
    my ( $self, $field, $value ) = @_;
    $self->{ _request }->header( $field, $value );
}

# content_type() getter
sub content_type($)
{
    my ( $self ) = @_;
    return $self->{ _request }->content_type();
}

# content_type() setter
sub set_content_type($$)
{
    my ( $self, $content_type ) = @_;
    $self->{ _request }->content_type( $content_type );
}

# content() getter
sub content($)
{
    my ( $self ) = @_;

    return $self->{ _request }->content();
}

# content() setter
#
# If it's an hashref, URL-encode it first.
sub set_content($$)
{
    my ( $self, $content ) = @_;

    if ( ref( $content ) eq ref( {} ) )
    {

        my @pairs;
        for my $key ( keys %{ $content } )
        {
            $key //= '';
            my $value = $content->{ $key } // '';
            push( @pairs, join( '=', map { uri_escape( $_ ) } $key, $value ) );
        }
        $content = join( '&', @pairs );
    }

    $self->{ _request }->content( $content );
}

# Set content, encode it to UTF-8 first
sub set_content_utf8($$)
{
    my ( $self, $content ) = @_;

    if ( ref( $content ) eq ref( {} ) )
    {
        my $encoded_content = {};

        for my $key ( keys %{ $content } )
        {
            $key //= '';
            my $value = $content->{ $key } // '';

            $encoded_content->{ encode_utf8( $key ) } = encode_utf8( $value );
        }

        $content = $encoded_content;
    }
    else
    {
        $content = encode_utf8( $content );
    }

    return $self->set_content( $content );
}

# No authorization_basic() getter

# authorization_basic() setter
sub set_authorization_basic($$$)
{
    my ( $self, $username, $password ) = @_;
    $self->{ _request }->authorization_basic( $username, $password );
}

# Alias for as_string()
sub as_string($)
{
    my ( $self ) = @_;
    return $self->{ _request }->as_string();
}

1;
