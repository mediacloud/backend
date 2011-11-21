package MediaWords::Util::Web;
use MediaWords::CommonLibs;


# various functions for editing feed and medium tags

use strict;

use File::Temp;
use FindBin;
use Storable;

# get urls in parallel
sub ParallelGet
{
    my ( $urls ) = @_;

    my $web_store_input;
    my $results;
    for my $url ( @{ $urls } )
    {
        my $result = { url => $url, file => File::Temp::mktemp( '/tmp/MediaWordsUtilWebXXXXXXXX' ) };

        $web_store_input .= "$result->{ file }:$result->{ url }\n";

        push( @{ $results }, $result );
    }

    my $cmd = "'$FindBin::Bin'/../script/mediawords_web_store.pl";

    if ( !open( CMD, '|-', $cmd ) )
    {
        warn( "Unable to start $cmd: $!" );
        return;
    }

    print CMD $web_store_input;
    close( CMD );

    my $responses;
    for my $result ( @{ $results } )
    {
        my $response = Storable::retrieve( $result->{ file } );

        push( @{ $responses }, $response );

        unlink( $result->{ file } );
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
