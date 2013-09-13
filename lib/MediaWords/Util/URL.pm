package MediaWords::Util::URL;

use URI;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;

# do some simple transformations on a url to make it match other equivalent urls as well as possible
sub normalize_url
{
    my ( $url ) = @_;
    $url = lc( $url );

    $url =~ s/^(https?:\/\/)(www.?|article|news|archives?)\./$1/;

    $url =~ s/\#.*//;

    $url =~ s/\/+$//;

    return scalar( URI->new( $url )->canonical );
}

1;
