package MediaWords::Util::URL;

use URI;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;

# do some simple transformations on a url to make it match other equivalent urls as well as possible
sub normalize_url
{
    my ( $url ) = @_;
    $url = lc( $url );

    # r2.ly redirects throug the hostname, ala http://543.r2.ly
    if ( $url !~ /r2\.ly/ )
    {
        $url =~ s/^(https?:\/\/)(media|data|image|www|cdn|topic|article|news|archive|blog|video|\d+?).?\./$1/i;
    }

    $url =~ s/\#.*//;

    $url =~ s/\/+$//;

    return scalar( URI->new( $url )->canonical );
}

1;
