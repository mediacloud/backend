package MediaWords::Util::JSON;

#
# Utilities for encoding / decoding JSON
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Python;

use Encode;
use JSON::XS qw//;    # don't import encode_json() and decode_json() into current namespace
use Data::Dumper;

# Encode hashref to JSON, die() on error
sub encode_json($;$$)
{
    my ( $object, $pretty, $utf8 ) = @_;

    # Do a deep copy in order to convert Inline::Python::Boolean to ints
    my $cast_bools_to_int = 1;
    $object = python_deep_copy( $object, $cast_bools_to_int );

    $pretty = ( $pretty ? 1 : 0 );
    $utf8   = ( $utf8   ? 1 : 0 );    # if you set this to 1, make sure you don't double-encode

    unless ( ref( $object ) eq ref( {} ) or ref( $object ) eq ref( [] ) )
    {
        die "Object is neither a hashref nor an arrayref: " . Dumper( $object );
    }

    my $json;
    eval {
        $json = JSON::XS->new->utf8( $utf8 )->pretty( $pretty )->allow_blessed( 1 )->convert_blessed( 1 )->canonical( 1 )
          ->encode( $object );
    };
    if ( $@ or ( !$json ) )
    {
        die "Unable to encode object to JSON: $@\nObject: " . Dumper( $object );
    }

    return $json;
}

# Decode JSON to hashref, die() on error
sub decode_json($;$)
{
    my ( $json, $utf8 ) = @_;

    $utf8 = ( $utf8 ? 1 : 0 );    # if you set this to 1, make sure you don't double-encode

    unless ( $json )
    {
        die "JSON is empty or undefined.\n";
    }

    my $hashref;
    eval { $hashref = JSON::XS->new->utf8( $utf8 )->decode( $json ); };
    if ( $@ or ( !$hashref ) )
    {
        die "Unable to decode JSON to object: $@";
    }

    return $hashref;
}

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
