package MediaWords::Solr::Request;

#
# Do GET / POST requests to Solr
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::Util::Config::Common;

Readonly my $QUERY_HTTP_TIMEOUT => 900;


sub _get_solr_url
{
    my $common_config = MediaWords::Util::Config::Common::CommonConfig();
    my $url = $common_config->solr_url();

    $url =~ s~/+$~~;

    return $url;
}

# Parse out Solr error message from response
sub _solr_error_message_from_response($)
{
	my $response = shift;

	my $error_message;

    if ( $response->error_is_client_side() )
    {

        # LWP error (LWP wasn't able to connect to the server or something like that)
        $error_message = 'LWP error: ' . $res->decoded_content;

    }
    else
    {

        my $status_code = $response->code;
        if ( $status_code =~ /^4\d\d$/ )
        {
            # Client error - set default message
            $error_message = 'Client error: ' . $response->status_line . ' ' . $response->decoded_content;

            # Parse out Solr error message if there is one
            my $solr_response_maybe_json = $response->decoded_content;
            if ( $solr_response_maybe_json )
            {
                my $solr_response_json;

                eval { $solr_response_json = MediaWords::Util::ParseJSON::decode_json( $solr_response_maybe_json ) };
                unless ( $@ )
                {
                    if (    exists( $solr_response_json->{ error }->{ msg } )
                        and exists( $solr_response_json->{ responseHeader }->{ params } ) )
                    {
                        my $solr_error_msg = $solr_response_json->{ error }->{ msg };
                        my $solr_params =
                          MediaWords::Util::ParseJSON::encode_json(
                            $solr_response_json->{ responseHeader }->{ params } );

                        # If we were able to decode Solr error message, overwrite the default error message with it
                        $error_message = 'Solr error: "' . $solr_error_msg . '", params: ' . $solr_params;
                    }
                }
            }

        }
        elsif ( $status_code =~ /^5\d\d/ )
        {
            # Server error or some other error
            $error_message = 'Server / other error: ' . $response->status_line . ' ' . $response->decoded_content;
        }
    }

    return $error_message;	
}

# Send a request to Solr. Return content on success, die() on error.
sub solr_request($$;$$)
{
    my ( $path, $params, $content, $content_type ) = @_;

    my $solr_url = _get_solr_url();
    $params //= {};

    my $abs_uri = URI->new( "$solr_url/mediacloud/$path" );
    $abs_uri->query_form( $params );
    my $abs_url = $abs_uri->as_string;

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_timeout( $QUERY_HTTP_TIMEOUT );
    $ua->set_max_size( undef );

    # Remediate CVE-2017-12629
    if ( $params->{ q } )
    {
        if ( $params->{ q } =~ /xmlparser/i )
        {
            LOGCONFESS "XML queries are not supported.";
        }
    }

    TRACE "Requesting URL: $abs_url...";

    my $request;
    if ( $content )
    {
        $content_type ||= 'text/plain; charset=utf-8';

        $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $abs_url );
        $request->set_header( 'Content-Type',   $content_type );
        $request->set_header( 'Content-Length', bytes::length( $content ) );
        $request->set_content_utf8( $content );
    }
    else
    {
        $request = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $abs_url );
    }

    my $response = $ua->request( $request );

    TRACE "query returned in " . tv_interval( $t0, [ gettimeofday ] ) . "s.";

    unless ( $response->is_success )
    {
        my $error_message = _solr_error_message_from_response( $response );
        die "Error fetching Solr response: $error_message";
    }

    return $response->decoded_content;
}

1;
