package MediaWords::Util::ParseJSON;

#
# Utilities for encoding / decoding JSON
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.parse_json' );

# numify the given fields in the given list of hashes so that encode_json() will encode them as
# numbers rather than strings
sub numify_fields($$)
{
    my ( $hashes, $numify_fields ) = @_;

    for my $hash ( @{ $hashes } )
    {
        map { $hash->{ $_ } += 0 if ( defined( $hash->{ $_ } ) ) } @{ $numify_fields };
    }
}

1;
