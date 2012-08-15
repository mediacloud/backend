package MediaWords::Util::Web;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# various functions for editing feed and medium tags

use strict;

use File::Temp;
use FindBin;
use Storable;
use MediaWords::Util::Paths;

# get urls in parallel
sub ParallelGet
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

    my $mc_script_path = MediaWords::Util::Paths::mc_script_path();
    my $cmd            = "'$mc_script_path'/../script/mediawords_web_store.pl";

    #say STDERR "opening cmd:'$cmd' ";

    if ( !open( CMD, '|-', $cmd ) )
    {
        warn( "Unable to start $cmd: $!" );
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

# walk back from the given response to get the original request that generated the response.
sub get_original_request
{
    my ( $class, $response ) = @_;

    my $original_response = $response;
    while ( $original_response->previous )
    {
        $original_response = $original_response->previous;
    }

    return $original_response->request;
}

1;
