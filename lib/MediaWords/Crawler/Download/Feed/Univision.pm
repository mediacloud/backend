package MediaWords::Crawler::Download::Feed::Univision;

#
# Handler for 'syndicated' feed downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::Download::DefaultFetcher', 'MediaWords::Crawler::Download::Feed::FeedHandler';

use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Util::DateTime;
use MediaWords::Util::URL;
use MediaWords::Util::Web;
use MediaWords::Util::ParseJSON;

use Data::Dumper;
use Date::Parse;
use Digest::SHA qw/sha1_hex/;
use Readonly;
use Readonly;
use URI::QueryParam;
use URI;

# Return API URL with request signature appended
sub _api_request_url_with_signature($$$;$)
{
    my ( $api_url, $client_id, $client_secret, $http_method ) = @_;

    unless ( $api_url and $client_id and $client_secret )
    {
        die "One or more required parameters are unset.";
    }

    unless ( MediaWords::Util::URL::is_http_url( $api_url ) )
    {
        die "API URL '$api_url' is not a HTTP(S) URL";
    }

    $http_method //= 'GET';

    my $uri = URI->new( $api_url );

    if ( $uri->query_param( 'client_id' ) )
    {
        die "Query already contains 'client_id'.";
    }

    $uri->query_param_append( 'client_id', $client_id );

    if ( length( $uri->path ) == 0 )
    {
        $uri->path( '/' );
    }
    my $api_url_path = $uri->path;

    # Sort query params as per API spec
    my @sorted_query_params;
    my @query_keys = $uri->query_param;
    for my $query_key ( sort @query_keys )
    {
        my @query_values = $uri->query_param( $query_key );
        for my $query_value ( sort @query_values )
        {
            push( @sorted_query_params, $query_key );
            push( @sorted_query_params, $query_value );
        }
    }

    TRACE 'Sorted query params: ' . join( ',', @sorted_query_params );

    $uri->query_form( \@sorted_query_params );

    TRACE "URI: " . $uri->as_string;

    my $api_url_query = $uri->query;

    my $unhashed_secret_key = $http_method . $client_id . $api_url_path . '?' . $api_url_query . $client_secret;
    TRACE "Unhashed secret key: $unhashed_secret_key";

    my $signature = sha1_hex( $unhashed_secret_key );
    TRACE "Signature (hashed secret key): $signature";

    $uri->query_param_append( 'signature', $signature );
    TRACE "API request URL: " . $uri->as_string;

    return $uri->as_string;
}

# Return API URL with request signature appended; Univision credentials are
# being read from configuration
sub _api_request_url_with_signature_from_config($;$)
{
    my ( $api_url, $http_method ) = @_;

    unless ( $api_url )
    {
        die "API (Univision feed) URL is unset.";
    }

    unless ( MediaWords::Util::URL::is_http_url( $api_url ) )
    {
        die "API (Univision feed) URL '$api_url' is not a HTTP(S) URL";
    }

    $http_method //= 'GET';

    my $config = MediaWords::Util::Config::get_config();

    my $client_id     = $config->{ univision }->{ client_id };
    my $client_secret = $config->{ univision }->{ client_secret };
    unless ( $client_id and $client_secret )
    {
        LOGDIE "Univision credentials are unset.";
    }

    return _api_request_url_with_signature( $api_url, $client_id, $client_secret, $http_method );
}

# Fetch Univision feed
sub fetch_download($$$)
{
    my ( $self, $db, $download ) = @_;

    $download->{ download_time } = MediaWords::Util::SQL::sql_now;
    $download->{ state }         = 'fetching';

    $db->update_by_id( 'downloads', $download->{ downloads_id }, $download );

    my $ua = MediaWords::Util::Web::UserAgent->new();

    Readonly my $http_method => 'GET';
    my $url_with_credentials = _api_request_url_with_signature_from_config( $download->{ url }, $http_method );

    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $url_with_credentials );
    my $response = $ua->request( $request );

    return $response;
}

# parse the feed.  return a (non-db-backed) story hash for each story found in the feed.
sub _get_stories_from_univision_feed($$$)
{
    my ( $decoded_content, $media_id, $download_time ) = @_;

    unless ( $decoded_content )
    {
        die "Feed content is empty or undefined.";
    }

    my $feed_json;
    eval { $feed_json = MediaWords::Util::ParseJSON::decode_json( $decoded_content ) };
    if ( $@ )
    {
        die "Unable to decode Univision feed JSON: $@";
    }

    unless ( $feed_json->{ 'status' } eq 'success' )
    {
        die "Univision feed response is not 'success': $decoded_content";
    }
    unless ( $feed_json->{ 'data' } )
    {
        die "Univision feed response does not have 'data' key";
    }
    unless ( $feed_json->{ 'data' }->{ 'items' } )
    {
        die "Univision feed response does not have 'data'/'items' key";
    }

    my $items = $feed_json->{ 'data' }->{ 'items' };

    my @stories;
    for my $item ( @{ $items } )
    {
        my $url = $item->{ 'url' };
        unless ( $url )
        {
            # Some items in the feed don't have their URLs set
            WARN "'url' for item is not set: " . Dumper( $item );
            next;
        }

        my $guid = $item->{ 'uid' } or die "Item does not have its 'uid' set.";
        my $title       = $item->{ 'title' }       // '(no title)';
        my $description = $item->{ 'description' } // '';

        my $str_publish_date = $item->{ 'publishDate' } or die "Item does not have its 'publishDate' set.";
        my $publish_date;
        eval {
            my $publish_timestamp = MediaWords::Util::DateTime::str2time_21st_century( $str_publish_date );
            $publish_date = MediaWords::Util::SQL::get_sql_date_from_epoch( $publish_timestamp );
        };
        if ( $@ )
        {
            # Die for good because Univision's dates should be pretty predictable
            die "Unable to parse item's publish date '$str_publish_date': $@";
        }

        TRACE "Story found in Univision feed: URL '$url', title '$title', publish date '$publish_date'";
        my $story = {
            url          => $url,
            guid         => $guid,
            media_id     => $media_id,
            publish_date => $publish_date,
            title        => $title,
            description  => $description,
        };

        push( @stories, $story );
    }

    return \@stories;
}

# Return new stories that were found in the feed
sub add_stories_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $media_id = MediaWords::DBI::Downloads::get_media_id( $db, $download );
    my $download_time = $download->{ download_time };

    my $stories;
    eval { $stories = _get_stories_from_univision_feed( $decoded_content, $media_id, $download_time ); };
    if ( $@ )
    {
        die "Error processing feed for $download->{ url }: $@";
    }

    my $new_story_ids = [];
    foreach my $story ( @{ $stories } )
    {
        $story = MediaWords::DBI::Stories::add_story_and_content_download( $db, $story, $download );
        push( @{ $new_story_ids }, $story->{ stories_id } ) if ( $story->{ is_new } );
    }

    return $new_story_ids;
}

sub return_stories_to_be_extracted_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    # Univision feed itself is not a story of any sort, so nothing to extract
    # (stories from this feed will be extracted as 'content' downloads)
    return [];
}

1;
