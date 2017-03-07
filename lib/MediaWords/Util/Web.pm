package MediaWords::Util::Web;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.util.web' );

use MediaWords::Util::Config;

=head1 NAME MediaWords::Util::Web - web related functions

=head1 DESCRIPTION

Various functions to make downloading web pages easier and faster, including parallel and cached fetching.

=cut

use Fcntl;
use File::Temp;
use FileHandle;
use FindBin;
use LWP::UserAgent;
use LWP::UserAgent::Determined;
use HTTP::Status qw(:constants);
use Storable;
use Readonly;

use MediaWords::Util::Config;
use MediaWords::Util::Paths;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

Readonly my $MAX_DOWNLOAD_SIZE => 10 * 1024 * 1024;    # Superglue (TV) feeds could grow big
Readonly my $TIMEOUT           => 20;
Readonly my $MAX_REDIRECT      => 15;

# on which HTTP codes should requests be retried
Readonly my @DETERMINED_HTTP_CODES => (

    HTTP_REQUEST_TIMEOUT,
    HTTP_INTERNAL_SERVER_ERROR,
    HTTP_BAD_GATEWAY,
    HTTP_SERVICE_UNAVAILABLE,
    HTTP_GATEWAY_TIMEOUT,
    HTTP_TOO_MANY_REQUESTS

);

=head1 FUNCTIONS

=cut

# handler callback assigned to prepare_request().
#
# this handler logs all http requests to a file and also invalidates any requests that match the regex in
# mediawords.yml->mediawords->blacklist_url_pattern.
sub _lwp_request_callback($)
{
    my ( $request, $ua, $h ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    my $blacklist_url_pattern = $config->{ mediawords }->{ blacklist_url_pattern };

    my $url = $request->uri->as_string;

    TRACE( "url: $url" );

    my $blacklisted;
    if ( $blacklist_url_pattern && ( $url =~ $blacklist_url_pattern ) )
    {
        $request->uri( "http://blacklistedsite.localhost/$url" );
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

    $fh->print( MediaWords::Util::SQL::sql_now . " $url\n" );
    $fh->print( "invalidating blacklist url.  stack: " . Carp::longmess . "\n" ) if ( $blacklisted );

    chmod( 0777, $logfile ) if ( $is_new_file );

    $fh->close;
}

=head2 user_agent()

Return a LWP::UserAgent::Determined (retries disabled by default) with
Media Cloud default settings for agent, timeout, max size, etc.

By calling timing(), e.g. timing('1,2,4,8'), one can reenable retries.

Uses custom callback to only retry after one of the following responses, which
indicate transient problem:

HTTP_REQUEST_TIMEOUT,
HTTP_INTERNAL_SERVER_ERROR,
HTTP_BAD_GATEWAY,
HTTP_SERVICE_UNAVAILABLE,
HTTP_GATEWAY_TIMEOUT

=cut

sub user_agent
{
    my $ua = LWP::UserAgent::Determined->new();

    my $config = MediaWords::Util::Config::get_config;

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

    # Won't be called if timing() is unset
    $ua->before_determined_callback(
        sub {
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args ) = @_;
            my $request = $lwp_args->[ 0 ];
            my $url     = $request->uri;

            TRACE "Trying $url ...";
        }
    );

    # Won't be called if timing() is unset
    $ua->after_determined_callback(
        sub {
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args, $response ) = @_;
            my $request = $lwp_args->[ 0 ];
            my $url     = $request->uri;

            unless ( $response->is_success )
            {
                my $will_retry = 0;
                if ( $codes_to_determinate->{ $response->code } )
                {
                    $will_retry = 1;
                }

                my $message = "Request to $url failed (" . $response->status_line . "), ";
                if ( response_error_is_client_side( $response ) )
                {
                    $message .= 'error is on the client side, ';
                }

                DEBUG( "$message " . ( ( $will_retry && $duration ) ? "retry in ${ duration }s" : "give up" ) );
                TRACE( "full response: " . $response->as_string );
            }
        }
    );

    return $ua;
}

=head2 parallel_get( $urls )

Get urls in parallel by using an external, forking script.  Returns a list of HTTP::Response objects resulting
from the fetches.

=cut

sub parallel_get
{
    my ( $urls ) = @_;

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
            $response = HTTP::Response->new( '500', "web store timeout for $result->{ url }" );
            $response->request( HTTP::Request->new( GET => $result->{ url } ) );

            push( @{ $responses }, $response );
        }
    }

    return $responses;
}

=head2 get_original_request( $request )

Walk back from the given response to get the original request that generated the response.

=cut

sub get_original_request($)
{
    my ( $response ) = @_;

    my $original_response = $response;
    while ( $original_response->previous )
    {
        $original_response = $original_response->previous;
    }

    return $original_response->request;
}

=head2 lookup_by_response_url( $list, $response )

Given a list of hashes, each of which includes a 'url' key, and an HTTP::Response, return the hash in $list for
which the canonical version of the url is the same as the canonical version of the originally requested
url for the response.  Return undef if no match is found.

This function is helpful for associating a given respone returned by parallel_get() with the object that originally
generated the url (for instance, the medium input record that generate the url fetch for the medium title)

=cut

sub lookup_by_response_url($$)
{
    my ( $list, $response ) = @_;

    my $original_request = get_original_request( $response );
    my $url              = URI->new( $original_request->uri->as_string );

    map { return ( $_ ) if ( URI->new( $_->{ url } ) eq $url ) } @{ $list };

    return undef;
}

=head2 response_error_is_client_side( $response )

Return true if the response's error was generated by LWP itself and not by the server.

=cut

sub response_error_is_client_side($)
{
    my $response = shift;

    if ( $response->is_success )
    {
        die "Response was successful, but I have expected an error.\n";
    }

    my $header_client_warning = $response->header( 'Client-Warning' );
    if ( defined $header_client_warning and $header_client_warning =~ /Internal response/ )
    {
        # Error was generated by LWP::UserAgent (created by user_agent());
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

=head2 get_meta_redirect_response( $response, $url )

If thee response has a meta tag or is an archive url, parse out the original url and treat it as a redirect
by inserting it into the response chain.   Otherwise, just return the original response.

=cut

sub get_meta_redirect_response
{
    my ( $response, $url ) = @_;

    unless ( $response->is_success )
    {
        return $response;
    }

    my $content = $response->decoded_content;

    for my $f ( \&MediaWords::Util::URL::meta_refresh_url_from_html, \&MediaWords::Util::URL::original_url_from_archive_url )
    {
        my $redirect_url = $f->( $content, $url );
        next unless ( $redirect_url );

        my $ua                = user_agent();
        my $redirect_response = $ua->get( $redirect_url );
        $redirect_response->previous( $response );

        $response = $redirect_response;
    }

    return $response;
}

1;
