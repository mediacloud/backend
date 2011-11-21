package MediaWords::Tagger::Yahoo;
use MediaWords::CommonLibs;


# generate tags for text using the yahoo term extractor

use LWP::UserAgent::Determined;
use XML::TreePP;

use strict;
use warnings;

use MediaWords::Util::Config;

my $_yahoo_term_url = 'http://search.yahooapis.com/ContentAnalysisService/V1/termExtraction';

# send the content to yahoo for term extraction
sub get_tags
{
    my ( $content ) = @_;

    #print "get_keywords_from_yahoo: $content\n";

    my $ua = LWP::UserAgent::Determined->new();

    my $key = MediaWords::Util::Config::get_config->{ mediawords }->{ yahoo_key };

    if ( !$key )
    {
        die( "no yahoo_key found in mediawords.yml" );
    }

    my $response = $ua->post( $_yahoo_term_url, { appid => $key, context => $content } );

    if ( !$response->is_success() )
    {
        return { error => "Error requesting yahoo term extraction url: " . $response->status_line() };
    }

    my $xml = new XML::TreePP();
    $xml->set( force_array => [ 'Result' ] );

    my $data = $xml->parse( $response->content() );

    if ( $data->{ Error } )
    {
        return { error => "Error returned from yahoo term extraction: " . $data->{ Error }->{ Message } };
    }

    #print "get_keywords_from_yahoo xml: " . $response->content() . "\n";

    if ( $data->{ ResultSet }->{ Result } )
    {
        return {
            tags    => [ sort { $a cmp $b } map { lc( $_ ) } @{ $data->{ ResultSet }->{ Result } } ],
            content => $response->content
        };
    }
    else
    {
        return { error => 'error parsing xml' };
    }
}

1;
