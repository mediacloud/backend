package MediaWords::Util::JSON;

#
# Utilities for encoding / decoding JSON
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Encode;
use JSON;
use Data::Dumper;

# Encode hashref to JSON, die() on error
sub encode_json($;$$)
{
    my ( $hashref, $pretty, $utf8 ) = @_;

    $pretty = ( $pretty ? 1 : 0 );
    $utf8   = ( $utf8   ? 1 : 0 );    # if you set this to 1, make sure you don't double-encode

    unless ( ref( $hashref ) eq ref( {} ) )
    {
        die "Parameter is not a hashref: " . Dumper( $hashref );
    }

    my $json;
    eval { $json = JSON->new->utf8( $utf8 )->pretty( $pretty )->encode( $hashref ); };
    if ( $@ or ( !$json ) )
    {
        die "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $hashref );
    }

    return $json;
}

# Decode JSON to hashref, die() on error
sub decode_json($;$)
{
    my ( $json, $utf8 ) = shift;

    $utf8 = ( $utf8 ? 1 : 0 );    # if you set this to 1, make sure you don't double-encode

    unless ( $json )
    {
        die "JSON is empty or undefined.\n";
    }

    my $hashref;
    eval { $hashref = JSON->new->utf8( $utf8 )->decode( $json ); };
    if ( $@ or ( !$hashref ) )
    {
        die "Unable to decode JSON to hashref: $@\nJSON: $json";
    }

    return $hashref;
}

1;
