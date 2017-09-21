package MediaWords::Util::CLIFF::Annotator;

#
# Fetch CLIFF annotations
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use URI;
use Scalar::Defer;
use Readonly;
use Data::Dumper;

use HTTP::Status qw(:constants);
use MediaWords::Util::CLIFF;
use MediaWords::Util::Config;
use MediaWords::Util::JSON;
use MediaWords::Util::Process;
use MediaWords::Util::Text;
use MediaWords::Util::Web;

# Requested text length limit (0 for no limit)
Readonly my $CLIFF_REQUEST_TEXT_LENGTH_LIMIT => 50 * 1024;

# (Lazy-initialized) CLIFF annotator URL
my $_cliff_annotator_url = lazy
{

    unless ( MediaWords::Util::CLIFF::cliff_is_enabled() )
    {
        fatal_error( "CLIFF annotator is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config::get_config();

    # CLIFF annotator URL
    my $url = $config->{ cliff }->{ annotator_url };
    unless ( $url )
    {
        die "Unable to determine CLIFF annotator URL to use.";
    }

    # Validate URL
    my $uri;
    eval { $uri = URI->new( $url )->canonical; };
    if ( $@ )
    {
        fatal_error( "Invalid CLIFF annotator URI '$url': $@" );
    }

    my $cliff_annotator_url = $uri->as_string;
    unless ( $cliff_annotator_url )
    {
        fatal_error( "CLIFF annotator is enabled, but annotator URL is not set." );
    }
    DEBUG "CLIFF annotator URL: $cliff_annotator_url";

    return $cliff_annotator_url;
};

# (Lazy-initialized) CLIFF annotator timeout
my $_cliff_annotator_timeout = lazy
{

    unless ( MediaWords::Util::CLIFF::cliff_is_enabled() )
    {
        fatal_error( "CLIFF annotator is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config::get_config();

    # Timeout
    my $cliff_annotator_timeout = $config->{ cliff }->{ annotator_timeout };
    unless ( $cliff_annotator_timeout )
    {
        die "Unable to determine CLIFF annotator timeout to set.";
    }
    DEBUG "CLIFF annotator timeout: $cliff_annotator_timeout s";

    return $cliff_annotator_timeout;
};

# Make a request to the CLIFF annotator, return hashref of parsed JSON results
#
# Parameters:
# * text to be annotated
#
# Returns: hashref with parsed annotator's JSON response, e.g.:
#
# {
#     "results": {
#         "organizations": [{
#             "count": 1,
#             "name": "United Nations"
#         }],
#         "places": {
#             "focus": {},
#             "mentions": []
#         },
#         "people": []
#     },
#     "status": "ok",
#     "milliseconds": 2,
#     "version": "2.3.0"
# }
#
# die()s on error
sub annotate_text($)
{
    my $text = shift;

    DEBUG "Annotating " . bytes::length( $text ) . " bytes of text...";

    unless ( $_cliff_annotator_url )
    {
        fatal_error( "Unable to determine CLIFF annotator URL to use." );
    }

    unless ( defined $text )
    {
        fatal_error( "Text is undefined." );
    }
    unless ( $text )
    {
        # CLIFF doesn't accept empty strings, but that might happen with some
        # stories so we're just die()ing here
        die "Text is empty.";
    }

    # Trim the text because that's what the CLIFF annotator will do, and
    # if the text is empty, we want to fail early without making a request
    # to the annotator at all
    $text =~ s/^\s+|\s+$//g;

    if ( $CLIFF_REQUEST_TEXT_LENGTH_LIMIT > 0 )
    {
        my $text_length = length( $text );
        if ( $text_length > $CLIFF_REQUEST_TEXT_LENGTH_LIMIT )
        {
            WARN "Text length ($text_length) has exceeded the request text " .
              "length limit ($CLIFF_REQUEST_TEXT_LENGTH_LIMIT) so I will truncate it.";
            $text = substr( $text, 0, $CLIFF_REQUEST_TEXT_LENGTH_LIMIT );
        }
    }

    unless ( MediaWords::Util::Text::is_valid_utf8( $text ) )
    {
        # Text will be encoded to JSON, so we test the UTF-8 validity before doing anything else
        die "Text is not a valid UTF-8 file: $text";
    }

    # Make a request
    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_timing( '1,2,4,8' );
    $ua->set_timeout( $_cliff_annotator_timeout );
    $ua->set_max_size( undef );

    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $_cliff_annotator_url );
    $request->set_content_type( 'application/x-www-form-urlencoded; charset=utf-8' );
    $request->set_content( { q => $text } );

    TRACE "Sending request to $_cliff_annotator_url...";
    my $response = $ua->request( $request );
    TRACE "Response received.";

    # Force UTF-8 encoding on the response because the server might not always
    # return correct "Content-Type"
    my $results_string = $response->decoded_utf8_content(
        charset         => 'utf8',
        default_charset => 'utf8'
    );

    unless ( $response->is_success )
    {
        # Error; determine whether we should be blamed for making a malformed
        # request, or is it an extraction error

        DEBUG "Request failed: " . $response->decoded_content;

        if ( lc( $response->status_line ) eq '500 read timeout' )
        {
            # die() on request timeouts without retrying anything
            # because those usually mean that we posted something funky
            # to the CLIFF annotator service and it got stuck
            LOGCONFESS "The request timed out, giving up; text length: " . bytes::length( $text ) . "; text: $text";
        }

        if ( $response->error_is_client_side() )
        {
            # Error was generated by the user agent client code; likely didn't reach server
            # at all (timeout, unresponsive host, etc.)
            fatal_error( 'LWP error: ' . $response->status_line . ': ' . $results_string );

        }
        else
        {
            # Error was generated by server

            my $http_status_code = $response->code;

            if ( $http_status_code == HTTP_METHOD_NOT_ALLOWED or $http_status_code == HTTP_BAD_REQUEST )
            {
                # Not POST, empty POST
                fatal_error( $response->status_line . ': ' . $results_string );

            }
            elsif ( $http_status_code == HTTP_INTERNAL_SERVER_ERROR )
            {
                # CLIFF processing error -- die() so that the error gets caught and logged into a database
                die 'CLIFF annotator service was unable to process the download: ' . $results_string;

            }
            else
            {
                # Shutdown the extractor on unconfigured responses
                fatal_error( 'Unknown HTTP response: ' . $response->status_line . ': ' . $results_string );
            }
        }
    }

    unless ( $results_string )
    {
        die "CLIFF annotator returned nothing for text: " . $text;
    }

    # Decode JSON response
    DEBUG "Decoding response from UTF-8...";
    eval { $results_string = Encode::decode_utf8( $results_string, Encode::FB_CROAK ); };
    if ( $@ )
    {
        fatal_error( "Unable to decode string '$results_string': $@" );
    }
    DEBUG "Done decoding response from UTF-8.";

    # Parse resulting JSON
    DEBUG "Parsing response's JSON...";
    my $results_hashref;
    eval { $results_hashref = MediaWords::Util::JSON::decode_json( $results_string ); };
    if ( $@ or ( !ref $results_hashref ) )
    {
        # If the JSON is invalid, it's probably something broken with the
        # remote CLIFF service, so that's why whe do fatal_error() here
        fatal_error( "Unable to parse JSON response: $@\nJSON string: $results_string" );
    }
    DEBUG "Done parsing response's JSON.";

    # Check sanity
    unless ( exists( $results_hashref->{ status } ) and lc( $results_hashref->{ status } ) eq 'ok' )
    {
        fatal_error( "Expected root key 'status' is missing / not 'ok' in JSON response: $results_string" );
    }
    unless ( exists( $results_hashref->{ results } ) and ref( $results_hashref->{ results } ) eq ref( {} ) )
    {
        fatal_error( "Expected root key 'results' is missing / not a hashref in JSON response: $results_string" );
    }

    DEBUG "Done annotating " . bytes::length( $text ) . " bytes of text.";

    return $results_hashref;
}

1;
