package MediaWords::Util::Web::UserAgent;

#
# Wrapper around LWP::UserAgent
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use Fcntl;
use File::Temp;
use FileHandle;
use HTTP::Status qw(:constants);
use List::MoreUtils qw/uniq/;
use LWP::Protocol::https;
use LWP::UserAgent::Determined;
use Readonly;
use Storable;
use URI;
use URI::Escape;

use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;
use MediaWords::Util::Web::UserAgent::Request;
use MediaWords::Util::Web::UserAgent::Response;

Readonly my $MAX_DOWNLOAD_SIZE => 10 * 1024 * 1024;    # Superglue (TV) feeds could grow big
Readonly my $MAX_REDIRECT      => 15;
Readonly my $MAX_HTML_REDIRECT => 7;
Readonly my $TIMEOUT           => 20;

# On which HTTP codes should requests be retried (if retrying is enabled)
Readonly my @DETERMINED_HTTP_CODES => (

    HTTP_REQUEST_TIMEOUT,
    HTTP_INTERNAL_SERVER_ERROR,
    HTTP_BAD_GATEWAY,
    HTTP_SERVICE_UNAVAILABLE,
    HTTP_GATEWAY_TIMEOUT,
    HTTP_TOO_MANY_REQUESTS

);

sub new
{
    my ( $class ) = @_;

    my $self = {};
    bless $self, $class;

    my $ua = LWP::UserAgent::Determined->new();

    my $config = MediaWords::Util::Config::get_config();

    $ua->from( $config->{ mediawords }->{ owner } );
    $ua->agent( $config->{ mediawords }->{ user_agent } );

    $ua->timeout( $TIMEOUT );
    $ua->max_size( $MAX_DOWNLOAD_SIZE );
    $ua->max_redirect( $MAX_REDIRECT );
    $ua->env_proxy;
    $ua->cookie_jar( {} );    # temporary cookie jar for an object
    $ua->default_header( 'Accept-Charset' => 'utf-8' );

    $ua->add_handler( request_prepare => \&_lwp_request_callback );

    # Disable retries by default; if client wants those, it should call
    # timing() itself, e.g. set it to '1,2,4,8'
    $ua->timing( '' );

    my %http_codes_hr = map { $_ => 1 } @DETERMINED_HTTP_CODES;
    $ua->codes_to_determinate( \%http_codes_hr );

    # Default "before" callback
    $self->{ _before_determined_callback } = sub {

        # Coming from ::Web::UserAgent
        my ( $ua, $request, $timing, $duration, $codes_to_determinate ) = @_;
        my $url = $request->url;

        TRACE "Trying $url ...";
    };

    # Won't be called if timing() is unset
    $ua->before_determined_callback(
        sub {
            # Coming from LWP::UserAgent
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args ) = @_;
            my $request = MediaWords::Util::Web::UserAgent::Request->new_from_http_request( $lwp_args->[ 0 ] );

            if ( defined $self->{ _before_determined_callback } )
            {
                $self->{ _before_determined_callback }->( $self, $request, $timing, $duration, $codes_to_determinate );
            }
        }
    );

    # Default "after" callback
    $self->{ _after_determined_callback } = sub {

        # Coming from ::Web::UserAgent
        my ( $ua, $request, $response, $timing, $duration, $codes_to_determinate ) = @_;

        my $url = $request->url;

        unless ( $response->is_success )
        {
            my $will_retry = 0;
            if ( $codes_to_determinate->{ $response->code } )
            {
                $will_retry = 1;
            }

            my $message = "Request to $url failed (" . $response->status_line . "), ";
            if ( $response->error_is_client_side() )
            {
                $message .= 'error is on the client side, ';
            }

            DEBUG "$message " . ( ( $will_retry && $duration ) ? "retry in ${ duration }s" : "give up" );
            TRACE "full response: " . $response->as_string;
        }
    };

    # Won't be called if timing() is unset
    $ua->after_determined_callback(
        sub {
            # Coming from LWP::UserAgent
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args, $response ) = @_;

            my $request = MediaWords::Util::Web::UserAgent::Request->new_from_http_request( $lwp_args->[ 0 ] );
            $response = MediaWords::Util::Web::UserAgent::Response->new_from_http_response( $response );

            if ( defined $self->{ _after_determined_callback } )
            {
                $self->{ _after_determined_callback }
                  ->( $self, $request, $response, $timing, $duration, $codes_to_determinate );
            }
        }
    );

    $self->{ _ua } = $ua;

    return $self;
}

# Handler callback assigned to request_prepare().
#
# This handler logs all http requests to a file and also invalidates any
# requests that match the regex in mediawords.yml->mediawords->blacklist_url_pattern.
sub _lwp_request_callback
{
    my ( $request, $ua, $h ) = @_;

    my $config = MediaWords::Util::Config::get_config();

    my $blacklist_url_pattern = $config->{ mediawords }->{ blacklist_url_pattern };

    my $url = $request->url;

    TRACE( "url: $url" );

    my $blacklisted;
    if ( $blacklist_url_pattern && ( $url =~ $blacklist_url_pattern ) )
    {
        $request->set_url( "http://blacklistedsite.localhost/$url" );
        $blacklisted = 1;
    }

    my $logfile = "$config->{ mediawords }->{ data_dir }/logs/http_request.log";

    my $fh = FileHandle->new;

    my $is_new_file = !( -f $logfile );

    if ( !$fh->open( ">>$logfile" ) )
    {
        ERROR( "unable to open log file '$logfile': $!" );
        return;
    }

    flock( $fh, Fcntl::LOCK_EX );

    $fh->print( MediaWords::Util::SQL::sql_now() . " $url\n" );
    $fh->print( "invalidating blacklist url.  stack: " . Carp::longmess . "\n" ) if ( $blacklisted );

    chmod( 0777, $logfile ) if ( $is_new_file );

    $fh->close;
}

# Alias for get()
sub get($$)
{
    my ( $self, $url ) = @_;
    my $response = $self->{ _ua }->get( $url );
    return MediaWords::Util::Web::UserAgent::Response->new_from_http_response( $response );
}

# Fetch the URL, evaluate HTTP / HTML redirects
# Returns response after all those redirects; die()s on error
sub get_follow_http_html_redirects($)
{
    my ( $self, $url ) = @_;

    unless ( defined $url )
    {
        die "URL is undefined.";
    }

    $url = MediaWords::Util::URL::fix_common_url_mistakes( $url );

    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        die "URL is not HTTP(s): $url";
    }

    if ( $self->max_redirect() == 0 )
    {
        die "User agent's max_redirect is 0, subroutine might loop indefinitely.";
    }

    my $orig_response = undef;
    for ( my $meta_redirect = 1 ; $meta_redirect <= $MAX_HTML_REDIRECT ; ++$meta_redirect )
    {
        my $response = $self->get( $url );
        unless ( $orig_response )
        {
            # Save first response for later use
            $orig_response = $response;
        }

        if ( $response->is_success )
        {

            my $new_url = $response->request()->url();
            unless ( $url eq $new_url )
            {
                TRACE "New URL: " . $new_url;
            }
            $url = $new_url;

            # Check if the returned document contains <meta http-equiv="refresh" />
            my $base_uri = URI->new( $url )->canonical;
            if ( $url !~ /\/$/ )
            {
                # In "http://example.com/first/two" URLs, strip the "two" part (but not when it has a trailing slash)
                my @base_uri_path_segments = $base_uri->path_segments;
                pop @base_uri_path_segments;
                $base_uri->path_segments( @base_uri_path_segments );
            }

            my $url_after_meta_redirect =
              MediaWords::Util::HTML::meta_refresh_url_from_html( $response->decoded_content(), $base_uri->as_string );
            if ( $url_after_meta_redirect and $url ne $url_after_meta_redirect )
            {
                TRACE "URL after <meta /> refresh: $url_after_meta_redirect";
                $url = $url_after_meta_redirect;

                # ...and repeat the HTTP redirect cycle
            }
            else
            {
                # No <meta /> refresh, the current URL is the final one
                return $response;
            }

        }
        else
        {

            my $redirects = $response->redirects();
            if ( scalar @{ $redirects } + 1 >= $self->max_redirect() )
            {
                my @urls_redirected_to;

                my $error_message = "";
                $error_message .= "Number of HTTP redirects (" . $self->max_redirect() . ") exhausted; redirects:\n";
                foreach my $redirect ( @{ $redirects } )
                {
                    push( @urls_redirected_to, $redirect->request()->url() );
                    $error_message .= "* From: " . $redirect->request()->url() . "; ";
                    $error_message .= "to: " . $redirect->header( 'Location' ) . "\n";
                }

                TRACE $error_message;

                # If one of the URLs that we've been redirected to contains another encoded URL, assume
                # that we're hitting a paywall and the URLencoded URL is the right one
                @urls_redirected_to = uniq @urls_redirected_to;
                foreach my $redirect ( @{ $redirects } )
                {
                    my $url_redirected_to         = $redirect->request()->url();
                    my $encoded_url_redirected_to = uri_escape( $url_redirected_to );

                    if ( my ( $matched_url ) = grep /$encoded_url_redirected_to/, @urls_redirected_to )
                    {
                        TRACE "Encoded URL $encoded_url_redirected_to is a substring of " .
                          "another URL $matched_url, so I'll assume that " . "$url_redirected_to is the correct one.";
                        return $redirect;

                    }
                }

                # Return the original URL (unless we find a URL being a substring of another URL, see below)
                return $orig_response;

            }
            else
            {
                TRACE "Request to $url was unsuccessful: " . $response->status_line;

                # Return the original URL and give up
                return $orig_response;
            }
        }
    }

    # Fallback
    return $orig_response;
}

# Get multiple URLs in parallel.
# Returns a list of response objects resulting from the fetches.
sub parallel_get($$)
{
    my ( $self, $urls ) = @_;

    return [] unless ( $urls && @{ $urls } );

    my $web_store_input;
    my $results;
    for my $url ( @{ $urls } )
    {
        my $result = { url => $url, file => File::Temp::mktemp( '/tmp/MediaWordsUtilWebXXXXXXXX' ) };

        $web_store_input .= "$result->{ file }:$result->{ url }\n";

        push( @{ $results }, $result );
    }

    my $mc_root_path = MediaWords::Util::Paths::mc_root_path();
    my $cmd          = "'$mc_root_path'/script/mediawords_web_store.pl";

    if ( !open( CMD, '|-', $cmd ) )
    {
        WARN "Unable to start $cmd: $!";
        return;
    }

    binmode( CMD, 'utf8' );

    print CMD $web_store_input;
    close( CMD );

    my $responses;
    for my $result ( @{ $results } )
    {
        my $response;
        if ( -f $result->{ file } )
        {
            $response = Storable::retrieve( $result->{ file } );
            push( @{ $responses }, $response );
            unlink( $result->{ file } );
        }
        else
        {
            my $http_response = HTTP::Response->new( '500', "web store timeout for $result->{ url }" );
            $response = MediaWords::Util::Web::UserAgent::Response->new_from_http_response( $http_response );
            $response->set_request( MediaWords::Util::Web::UserAgent::Request->new( 'GET', $result->{ url } ) );

            push( @{ $responses }, $response );
        }
    }

    return $responses;
}

# Returns URL content as string, undef on error
sub get_string($$)
{
    my ( $self, $url ) = @_;

    my $response = $self->get( $url );
    if ( $response->is_success )
    {
        return $response->decoded_content;
    }
    else
    {
        return undef;
    }
}

# Alias for post()
sub post($$)
{
    my ( $self, $url, $form_params ) = @_;

    unless ( ref( $form_params ) eq ref( {} ) )
    {
        LOGCONFESS "Form parameters is not a hashref: " . Dumper( $form_params );
    }

    my $response = $self->{ _ua }->post( $url, $form_params );
    return MediaWords::Util::Web::UserAgent::Response->new_from_http_response( $response );
}

# Alias for request()
sub request($$)
{
    my ( $self, $request ) = @_;

    unless ( ref( $request ) eq 'MediaWords::Util::Web::UserAgent::Request' )
    {
        LOGCONFESS "Request is not MediaWords::Util::Web::UserAgent::Request: " . Dumper( $request );
    }

    my $http_request = $request->http_request();
    my $response     = $self->{ _ua }->request( $http_request );
    return MediaWords::Util::Web::UserAgent::Response->new_from_http_response( $response );
}

# timing() getter
sub timing($)
{
    my ( $self ) = @_;
    return $self->{ _ua }->timing();
}

# timing() setter
sub set_timing($$)
{
    my ( $self, $timing ) = @_;
    $self->{ _ua }->timing( $timing );
}

# timeout() getter
sub timeout($)
{
    my ( $self ) = @_;
    return $self->{ _ua }->timeout();
}

# timeout() setter
sub set_timeout($$)
{
    my ( $self, $timeout ) = @_;
    $self->{ _ua }->timeout( $timeout );
}

# before_determined_callback() getter
sub before_determined_callback($)
{
    my ( $self ) = @_;
    return $self->{ _before_determined_callback };
}

# before_determined_callback() setter
sub set_before_determined_callback($$)
{
    my ( $self, $before_determined_callback ) = @_;
    $self->{ _before_determined_callback } = $before_determined_callback;
}

# after_determined_callback() getter
sub after_determined_callback($)
{
    my ( $self ) = @_;
    return $self->{ _after_determined_callback };
}

# after_determined_callback() setter
sub set_after_determined_callback($$)
{
    my ( $self, $after_determined_callback ) = @_;
    $self->{ _after_determined_callback } = $after_determined_callback;
}

# max_redirect() getter
sub max_redirect($)
{
    my ( $self ) = @_;
    return $self->{ _ua }->max_redirect();
}

# max_redirect() setter
sub set_max_redirect($$)
{
    my ( $self, $max_redirect ) = @_;
    $self->{ _ua }->max_redirect( $max_redirect );
}

# max_size() getter
sub max_size($)
{
    my ( $self ) = @_;
    return $self->{ _ua }->max_size();
}

# max_size() setter
sub set_max_size($$)
{
    my ( $self, $max_size ) = @_;
    $self->{ _ua }->max_size( $max_size );
}

1;
