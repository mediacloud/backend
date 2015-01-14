package MediaWords::Util::Twitter;

#
# Twitter API helper
#

use strict;
use warnings;

use URI;
use URI::QueryParam;
use URI::Escape;

use Readonly;
use Data::Dumper;
use Data::Compare;

use MediaWords::Util::JSON;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

sub _get_single_url_json
{
    my ( $ua, $url ) = @_;

    # this is mostly to be able to generate an error for testing
    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        die "Invalid URL: $url";
    }

    # Get canonical URL
    my $uri = URI->new( $url )->canonical;
    unless ( $uri )
    {
        die "Unable to create URI object for URL: $url";
    }

    # If there's no slash at the end of the URL, Twitter API will always add
    # it, so we might as well do it ourselves
    if ( substr( $uri->path . '', -1 ) ne '/' )
    {
        $uri->path( $uri->path . '/' );
    }

    $url = $uri->as_string;

    my $api_url = 'https://cdn.api.twitter.com/1/urls/count.json?url=' . uri_escape_utf8( $url );

    # say STDERR "API URL: " . $api_url;
    my $response = $ua->get( $api_url );

    unless ( $response->is_success )
    {
        die "error fetching tweet count for URL: $url";
    }
    my $decoded_content = $response->decoded_content;

    my $data = MediaWords::Util::JSON::decode_json( $decoded_content );
    unless ( $data and ref( $data ) eq ref( {} ) )
    {
        die "Returned JSON is empty or invalid.";
    }

    unless ( defined $data->{ url } and defined $data->{ count } )
    {
        die "Returned JSON doesn't have 'url' and / or 'count' keys for URL: $url; JSON: " . Dumper( $data );
    }

    my $returned_uri = URI->new( $data->{ url } )->canonical;
    unless ( $uri )
    {
        die "Unable to create URI object for returned URL: $data->{ url }";
    }

    unless ( $uri->eq( $returned_uri ) )
    {
        # Twitter sometimes reorders ?query=parameters, so compare them separately
        my $uri_without_query_params = $uri->clone;
        $uri_without_query_params->query( undef );
        my $returned_uri_without_query_params = $returned_uri->clone;
        $returned_uri->query( undef );

        # Don't compare URL #fragment if it doesn't start with a slash because
        # Twitter will strip it
        if ( $uri_without_query_params->fragment )
        {
            unless ( $uri_without_query_params->fragment =~ /^\// )
            {
                $uri_without_query_params->fragment( undef );
                $returned_uri_without_query_params->fragment( undef );
            }
        }

        unless ( $uri_without_query_params->eq( $returned_uri_without_query_params )
            and Compare( $uri_without_query_params->query_form_hash, $returned_uri_without_query_params->query_form_hash ) )
        {
            warn "Returned URL (" .
              $returned_uri->as_string . ") is not the same as requested URL (" . $uri_without_query_params->as_string . ")";
        }
    }

    return $data;
}

sub _get_single_url_tweet_count
{
    my ( $ua, $url ) = @_;

    # Skip homepage URLs
    if ( MediaWords::Util::URL::is_homepage_url( $url ) )
    {
        my $uri = URI->new( $url )->canonical;
        unless ( $uri )
        {
            die "Unable to create URI object for URL: $url";
        }

        # ...unless the #fragment part looks like a path because Twitter will
        # then accept those
        unless ( $uri->fragment and $uri->fragment =~ /^\// )
        {
            say STDERR "URL is homepage: $url";
            return 0;
        }
    }

    my $data = _get_single_url_json( $ua, $url );

    return $data->{ count };
}

# use cdn.api.twitter.com/1/urls/count.json to get count of tweets referencing the given url, including all variants
# of the url we can figure out
#
# https://cdn.api.twitter.com/1/urls/count.json?url=http://www.theonion.com/articles/how-to-protect-yourself-against-ebola,37085
sub get_url_tweet_count
{
    my ( $db, $url ) = @_;

    my $all_urls = [ MediaWords::Util::URL::all_url_variants( $db, $url ) ];

    my $ua = MediaWords::Util::Web::UserAgentDetermined();
    $ua->timing( '1,3,15,60,300,600' );

    my $url_counts = {};
    for my $u ( @{ $all_urls } )
    {
        my $count = _get_single_url_tweet_count( $ua, $u );

        say STDERR "* Count: $count, URL variant: $u";

        $url_counts->{ $count } = $u;
    }

    return List::Util::sum( keys( %{ $url_counts } ) );
}

sub get_and_store_tweet_count
{
    my ( $db, $story ) = @_;

    my $stories_id  = $story->{ stories_id };
    my $stories_url = $story->{ url };

    my $count;
    eval { $count = get_url_tweet_count( $db, $stories_url ); };
    my $error = $@ ? $@ : undef;

    $count ||= 0;

    $db->query( <<END, $stories_id, $count, $error );
with try_update as (
  update story_statistics 
        set twitter_url_tweet_count = \$2, twitter_url_tweet_count_error = \$3
        where stories_id = \$1
        returning *
)
insert into story_statistics ( stories_id, twitter_url_tweet_count, twitter_url_tweet_count_error )
    select \$1, \$2, \$3
        where not exists ( select * from try_update );
END

    if ( $error )
    {
        die "Error while fetching Twitter stats for story $stories_id ($stories_url): $error";
    }

    return $count;

}

1;
