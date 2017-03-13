package MediaWords::Util::Web;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.util.web' );

=head1 NAME MediaWords::Util::Web - web related functions

=head1 DESCRIPTION

Various functions to make downloading web pages easier and faster, including parallel and cached fetching.

=cut

use File::Temp;
use FindBin;
use Readonly;
use Storable;

use MediaWords::Util::Paths;

{
    # Wrapper around HTTP::Request
    package MediaWords::Util::Web::UserAgent::Request;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use Data::Dumper;
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
}

{
    # Wrapper around HTTP::Response
    package MediaWords::Util::Web::UserAgent::Response;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use Data::Dumper;

    sub new_from_http_response
    {
        my ( $class, $response ) = @_;

        unless ( ref( $response ) eq 'HTTP::Response' )
        {
            LOGCONFESS "Response is not HTTP::Response: " . Dumper( $response );
        }

        my $self = {};
        bless $self, $class;

        $self->{ _response } = $response;

        if ( $response->request() )
        {
            $self->{ _request } = MediaWords::Util::Web::UserAgent::Request->new_from_http_request( $response->request() );
        }
        if ( $response->previous() )
        {
            $self->{ _previous } =
              MediaWords::Util::Web::UserAgent::Response->new_from_http_response( $response->previous() );
        }

        return $self;
    }

    # code() getter
    sub code($)
    {
        my ( $self ) = @_;
        return $self->{ _response }->code();
    }

    # message() getter
    sub message($)
    {
        my ( $self ) = @_;
        return $self->{ _response }->message();
    }

    # header() getter
    sub header($$)
    {
        my ( $self, $field ) = @_;
        return $self->{ _response }->header( $field );
    }

    # decoded_content() getter
    sub decoded_content($)
    {
        my ( $self ) = @_;
        return $self->{ _response }->decoded_content();
    }

    # decoded_content() getter with enforced UTF-8 response
    sub decoded_utf8_content($)
    {
        my ( $self ) = @_;
        return $self->{ _response }->decoded_content(
            charset         => 'utf8',
            default_charset => 'utf8'
        );
    }

    # status_line() getter
    sub status_line($)
    {
        my ( $self ) = @_;
        return $self->{ _response }->status_line();
    }

    # is_success() getter
    sub is_success($)
    {
        my ( $self ) = @_;
        return $self->{ _response }->is_success();
    }

    # Alias for as_string()
    sub as_string($)
    {
        my ( $self ) = @_;
        return $self->{ _response }->as_string();
    }

    # Alias for redirects(), returns arrayref instead of array though
    sub redirects($)
    {
        my ( $self ) = @_;
        my @redirects = $self->{ _response }->redirects();
        return \@redirects;
    }

    # Alias for content_type()
    sub content_type($)
    {
        my ( $self ) = @_;
        return $self->{ _response }->content_type();
    }

    # previous() getter
    sub previous($)
    {
        my ( $self ) = @_;
        return $self->{ _previous };
    }

    # previous() setter
    sub set_previous($$)
    {
        my ( $self, $previous ) = @_;

        unless ( ref( $previous ) eq 'MediaWords::Util::Web::UserAgent::Response' )
        {
            LOGCONFESS "Previous response is not MediaWords::Util::Web::UserAgent::Response: " . Dumper( $previous );
        }
        $self->{ _previous } = $previous;
    }

    # request() getter
    sub request($)
    {
        my ( $self ) = @_;
        return $self->{ _request };
    }

    # request() setter
    sub set_request($$)
    {
        my ( $self, $request ) = @_;

        unless ( ref( $request ) eq 'MediaWords::Util::Web::UserAgent::Request' )
        {
            LOGCONFESS "Request is not MediaWords::Util::Web::UserAgent::Request: " . Dumper( $request );
        }
        $self->{ _request } = $request;
    }

    # Walk back from the given response to get the original request that generated the response.
    sub original_request($)
    {
        my ( $self ) = @_;

        my $original_response = $self;
        while ( $original_response->previous() )
        {
            $original_response = $original_response->previous();
        }

        return $original_response->request();
    }

    # Return true if the response's error was generated by LWP itself and not by the server.
    sub error_is_client_side($)
    {
        my ( $self ) = @_;

        if ( $self->is_success )
        {
            LOGCONFESS "Response was successful, but I have expected an error.";
        }

        my $header_client_warning = $self->header( 'Client-Warning' );
        if ( defined $header_client_warning and $header_client_warning =~ /Internal response/ )
        {
            # Error was generated by LWP::UserAgent;
            # likely we didn't reach server at all (timeout, unresponsive host,
            # etc.)
            #
            # http://search.cpan.org/~gaas/libwww-perl-6.05/lib/LWP/UserAgent.pm#$ua->get(_$url_)
            return 1;
        }
        else
        {
            return 0;
        }
    }

    1;
}

{
    # Wrapper around LWP::UserAgent
    package MediaWords::Util::Web::UserAgent;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use Data::Dumper;
    use Fcntl;
    use FileHandle;
    use HTTP::Status qw(:constants);
    use LWP::UserAgent::Determined;
    use LWP::Protocol::https;
    use Readonly;

    use MediaWords::Util::Config;
    use MediaWords::Util::SQL;

    Readonly my $MAX_DOWNLOAD_SIZE => 10 * 1024 * 1024;    # Superglue (TV) feeds could grow big
    Readonly my $MAX_REDIRECT      => 15;
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
}

1;
