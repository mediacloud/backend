#!/usr/bin/perl

# add alexa traffic data to the sopa_media_alexa_traffic table for every medium in sopa_stories

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Digest::SHA qw(hmac_sha256_base64);
use File::Basename;
use LWP::UserAgent::Determined;
use URI::Escape;
use XML::XPath;
use XML::XPath::XMLParser;

use MediaWords::DB;

use constant AWIS_SERVER => "awis.amazonaws.com";

# Returns the AWS URL to get the site list for the specified country
sub compose_url
{
    my ( $url, $access_key, $secret_key ) = @_;

    my $uri = {
        Action           => 'TrafficHistory',
        ResponseGroup    => 'History',
        AWSAccessKeyId   => $access_key,
        Timestamp        => generate_timestamp(),
        SignatureVersion => 2,
        SignatureMethod  => 'HmacSHA256',
        Url              => $url,
        Start            => '2012-01-01',
        Range            => 30
    };

    # http://awis.amazonaws.com/?
    #             Action=TrafficHistory
    #             &AWSAccessKeyId=[Your AWS Access Key ID]
    #             &Signature=[signature calculated from request]
    #             &SignatureMethod=[HmacSha1 or HmacSha256]
    #             &SignatureVersion=2
    #             &Timestamp=[timestamp used in signature]
    #             &Url=[Valid URL]
    #             &ResponseGroup=History
    #             &Range=[maximum number of results]
    #             &Start=[start date for results]

    my $params = [];

    #sort hash and uri escape
    foreach my $key ( sort keys %{ $uri } )
    {
        push( @{ $params }, escape( $key ) . '=' . escape( $uri->{ $key } ) );
    }

    my $param_string = join( '&', @{ $params } );
    my $request_string = "GET\n" . AWIS_SERVER . "\n/\n" . $param_string;

    $param_string .= '&Signature=' . escape( digest( $request_string, $secret_key ) );

    return 'http://' . AWIS_SERVER . '/?' . $param_string;
}

# Calculate current TimeStamp
sub generate_timestamp
{
    return sprintf(
        "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
        sub {
            ( $_[ 5 ] + 1900, $_[ 4 ] + 1, $_[ 3 ], $_[ 2 ], $_[ 1 ], $_[ 0 ] );
          }
          ->( gmtime( time ) )
    );
}

# URI escape only the characters that should be escaped, according to RFC 3986
sub escape
{
    my ( $str ) = @_;
    return uri_escape_utf8( $str, '^A-Za-z0-9\-_.~' );
}

# The digest is the signature
sub digest
{
    my ( $query, $secret_key ) = @_;
    my $digest = hmac_sha256_base64( $query, $secret_key );

    # Digest::MMM modules do not pad their base64 output, so we do
    # it ourselves to keep the service happy.
    return $digest . "=";
}

sub get_traffic_data_for_url
{
    my ( $url, $access_key, $secret_key ) = @_;

    my $request_url = compose_url( $url, $access_key, $secret_key );

    my $user_agent = LWP::UserAgent::Determined->new;

    $user_agent->timing( '1,2,5,10,30' );

    my $request = HTTP::Request->new( 'GET', $request_url );
    my $response = $user_agent->request( $request );

    my $link = "";

    if ( !$response->is_success )
    {
        warn( "Request failed for '$url': $response->as_string" );
        return undef;
    }

    my $output = $response->decoded_content;

    # print STDERR $output;

    my $xp = XML::XPath->new( xml => $output );

    my $dates         = [];
    my $date_node_set = $xp->find(
'/aws:TrafficHistoryResponse/aws:Response/aws:TrafficHistoryResult/aws:Alexa/aws:TrafficHistory/aws:HistoricalData/aws:Data'
    );

    for my $date_node ( $date_node_set->get_nodelist )
    {
        my $date = {
            day                    => $date_node->findvalue( 'aws:Date' )->value,
            rank                   => $date_node->findvalue( 'aws:Rank' )->value,
            page_views_per_user    => $date_node->findvalue( 'aws:PageViews/aws:PerUser' )->value || 0,
            page_views_per_million => $date_node->findvalue( 'aws:PageViews/aws:PerMillion' )->value || 0,
            reach_per_million      => $date_node->findvalue( 'aws:Reach/aws:PerMillion' )->value || 0
        };

        map { $date->{ $_ } = 1 if ( $date->{ $_ } eq 'NaN' ) }
          qw(page_views_per_million page_view_per_user reach_per_million);

        push( @{ $dates }, $date );
    }

    return $dates;
}

sub get_sopa_media
{
    my ( $db ) = @_;

    return $db->query( "select distinct m.* from media m, sopa_stories ss, stories s " .
          "  where m.media_id = s.media_id and s.stories_id = ss.stories_id limit 10" )->hashes;
}

sub add_missing_alexa_data_to_medium
{
    my ( $db, $medium, $access_key, $secret_key ) = @_;

    print STDERR "checking $medium->{ name }\n";

    return if ( $db->query( "select * from media_alexa_stats where media_id = ?", $medium->{ media_id } )->hash );

    print STDERR "fetching $medium->{ url }\n";
    my $alexa_data = get_traffic_data_for_url( $medium->{ url }, $access_key, $secret_key );

    for my $alexa_date ( @{ $alexa_data } )
    {
        print STDERR Dumper( $alexa_date );
        $alexa_date->{ media_id } = $medium->{ media_id };
        $db->create( 'media_alexa_stats', $alexa_date );
    }
}

sub main
{
    my ( $access_key, $secret_key ) = @ARGV;

    die( "usage: $0 <access key> <secret key>" ) if ( @ARGV < 2 );

    my $db = MediaWords::DB::connect_to_db;

    my $media = get_sopa_media( $db );

    for my $medium ( @{ $media } )
    {
        add_missing_alexa_data_to_medium( $db, $medium, $access_key, $secret_key );
    }
}

main();

