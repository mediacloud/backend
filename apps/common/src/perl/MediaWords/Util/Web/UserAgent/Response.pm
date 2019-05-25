package MediaWords::Util::Web::UserAgent::Response;

#
# HTTP response
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Web::UserAgent::Request;

{

    package MediaWords::Util::Web::UserAgent::Response::Proxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.util.web.user_agent.response.response' );

    1;
}

# No new() because Python responses get created using urllib3's response object

sub from_python_response($$)
{
    my ( $class, $python_response ) = @_;

    if ( $python_response )
    {
        my $self = {};
        bless $self, $class;

        $self->{ _response } = $python_response;

        return $self;
    }
    else
    {
        return undef;
    }
}

sub python_response()
{
    my ( $self ) = @_;

    return $self->{ _response };
}

sub code($)
{
    my ( $self ) = @_;

    return $self->{ _response }->code();
}

sub message($)
{
    my ( $self ) = @_;

    return $self->{ _response }->message();
}

sub header($$)
{
    my ( $self, $field ) = @_;

    return $self->{ _response }->header( $field );
}

sub decoded_content($)
{
    my ( $self ) = @_;

    return $self->{ _response }->decoded_content();
}

sub decoded_utf8_content($)
{
    my ( $self ) = @_;

    return $self->{ _response }->decoded_utf8_content();
}

sub status_line($)
{
    my ( $self ) = @_;

    return $self->{ _response }->status_line();
}

sub is_success($)
{
    my ( $self ) = @_;

    return $self->{ _response }->is_success();
}

sub content_type($)
{
    my ( $self ) = @_;

    return $self->{ _response }->content_type();
}

sub previous($)
{
    my ( $self ) = @_;

    my $python_response = $self->{ _response }->previous();

    if ( $python_response )
    {
        my $response = MediaWords::Util::Web::UserAgent::Response->from_python_response( $python_response );
        return $response;
    }
    else
    {
        return undef;
    }
}

sub set_previous($$)
{
    my ( $self, $previous ) = @_;

    my $python_response;
    if ( $previous )
    {
        $python_response = $previous->{ _response };
    }
    else
    {
        $python_response = undef;
    }

    $self->{ _response }->set_previous( $python_response );
}

sub request($)
{
    my ( $self ) = @_;

    my $python_request = $self->{ _response }->request();

    my $request = MediaWords::Util::Web::UserAgent::Request->from_python_request( $python_request );
    return $request;
}

sub set_request($$)
{
    my ( $self, $request ) = @_;

    my $python_request;
    if ( $request )
    {
        $python_request = $request->python_request();
    }
    else
    {
        $python_request = undef;
    }

    $self->{ _response }->set_request( $python_request );
}

sub original_request($)
{
    my ( $self ) = @_;

    my $python_request = $self->{ _response }->original_request();

    my $request = MediaWords::Util::Web::UserAgent::Request->from_python_request( $python_request );
    return $request;
}

sub error_is_client_side($)
{
    my ( $self ) = @_;

    return $self->{ _response }->error_is_client_side();
}

1;
