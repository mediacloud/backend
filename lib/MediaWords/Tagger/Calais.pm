package MediaWords::Tagger::Calais;
use MediaWords::CommonLibs;

use strict;

# generate tags for text using calais

use Encode;
use HTTP::Request::Common;
use URI::Escape;
use URI::Split;
use XML::TreePP;
use RDF::Simple::Parser;
use Net::Calais;
use DateTime;

use MediaWords::Util::Config;

use List::Util qw (min max);

#specifies the maximum time that we will wait before retrying a request
use constant MAX_WAIT_SECONDS => 60 * 60 * 3;

# number of times to retry when we get an overlimit error
use constant MAX_OVERLIMIT_RETRIES => 25;

# number of times to retry when we get any non-overlimit error
use constant MAX_ERROR_RETRIES => 10;

# string in calais response that indicates an overlimit error
use constant CALAIS_OVERLIMIT_ERROR => "403 Forbidden";

# try to fetch the tags from calais once
sub fetch_tags
{
    my ( $content ) = @_;

    $content =~ s/[^[:ascii:]]/ /g;

    my $key = MediaWords::Util::Config::get_config->{ mediawords }->{ calais_key };

    #Uncomment this line to change the opencalais server.  We needed this in the 4.0 change over but probably don't now...
    #$Net::Calais::CALAIS_URL = 'http://api1.opencalais.com/enlighten/rest/';

    my $calais = Net::Calais->new( apikey => $key );

    my $calais_response;
    {
        no warnings;
        $calais_response = $calais->enlighten( $content, contentType => "text/txt", outputFormat => "xml/rdf" );
    }

    if ( !$calais_response )
    {
        if ( $calais->{ error } eq CALAIS_OVERLIMIT_ERROR )
        {
            return { error => "over calais request limit", overlimit => 1 };
        }
        else
        {
            return { error => "Calais error: $calais->{error}" };
        }
    }

    if ( index( $calais_response, '<Exception>' ) > 0 )
    {
        return { error => "Calais exception: $calais_response" };
    }

    my $begin_terms = index( $calais_response, '-->' ) + 7;
    my $end_terms = index( $calais_response, '-->', $begin_terms );
    my $terms = substr( $calais_response, $begin_terms, $end_terms - $begin_terms );

    my $tags = {};
    while ( $terms =~ /(\w+): (.+)/ig )
    {

        # Relations are just relation type headers e.g. 'Company' so we don't want them to be tags
        next if ( $1 eq 'Relations' );

     # Position relations i.e. job titles such as 'president Chief of Staff , Democratic leader' are noise to us so skip them
        next if ( $1 eq 'Position' );

        for my $t ( map { lc( $_ ) } split( ', ', $2 ) )
        {
            if ( ( $t !~ /^[a-z]+\:\/\// ) & ( $t !~ /\@/ ) )
            {
                $t =~ s/^(\s+)//;
                $t =~ s/(\s+)$//;
                $t =~ s/(\s+)/ /g;

                if ( $t )
                {
                    $tags->{ $t } = 1;
                }
            }
        }
    }

    return {
        tags => [ sort { $a cmp $b } ( keys( %{ $tags } ) ) ],
        content => $calais_response
    };
}

sub get_tags
{
    my ( $content ) = @_;

    my $tags;

    for ( my $i = 0 ; 1 ; $i++ )
    {
        $tags = fetch_tags( $content );

        if ( $tags->{ tags } )
        {
            return $tags;
        }
        elsif ( $tags->{ overlimit } )
        {
            if ( $i >= MAX_OVERLIMIT_RETRIES )
            {
                last;
            }
        }
        elsif ( $i >= MAX_ERROR_RETRIES )
        {
            last;
        }

        sleep min( ( 2**$i ), MAX_WAIT_SECONDS );
    }

    return { error => "too many errors from calais.  last error: " . $tags->{ error } };
}

1;
