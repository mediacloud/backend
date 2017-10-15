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
use LWP::Protocol::https;
use LWP::UserAgent::Determined;
use Readonly;
use Storable;

use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::Util::Web::UserAgent::Request;
use MediaWords::Util::Web::UserAgent::Response;

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

    # Callbacks won't be called if timing() is unset

    $ua->before_determined_callback(
        sub {

            # Coming from LWP::UserAgent
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args ) = @_;

            my $request = MediaWords::Util::Web::UserAgent::Request->new_from_http_request( $lwp_args->[ 0 ] );

            my $url = $request->url;

            TRACE "Trying $url ...";
        }
    );

    $ua->after_determined_callback(
        sub {

            # Coming from LWP::UserAgent
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args, $response ) = @_;

            my $request = MediaWords::Util::Web::UserAgent::Request->new_from_http_request( $lwp_args->[ 0 ] );
            $response = MediaWords::Util::Web::UserAgent::Response->new_from_http_response( $response );

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

            INFO( "parallel_get stored response: " . ref( $response ) );

            push( @{ $responses }, $response );

            if ( $response )
            {
                unlink( $result->{ file } );
            }
            else
            {
                INFO( "undefined response for file $result->{ file }, skipping unlink" );
            }
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
