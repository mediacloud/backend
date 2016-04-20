use strict;
use warnings;
use utf8;

use Test::NoWarnings;
use Readonly;
use Test::More tests => 6;
use Test::Deep;
use Data::Dumper;
use Encode;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::JSON' );
}

sub test_encode_decode_json()
{
    my $object = [
        'foo' => { 'bar' => 'baz', },
        'xyz' => 'zyx',
        'moo',
        'ąčęėįšųūž',
        42
    ];
    my $expected_json = '["foo",{"bar":"baz"},"xyz","zyx","moo","ąčęėįšųūž",42]';

    my $utf8;
    my $pretty = 0;
    my ( $encoded_json, $decoded_json );

    # With UTF-8 flag
    $utf8 = 1;
    $encoded_json = MediaWords::Util::JSON::encode_json( $object, $pretty, $utf8 );
    is( $encoded_json, encode( 'utf-8', $expected_json ), 'encode_json() with UTF-8 flag' );
    $decoded_json = MediaWords::Util::JSON::decode_json( $encoded_json, $utf8 );
    cmp_deeply( $decoded_json, $object, 'decode_json() with UTF-8 flag' );

    # Without UTF-8 flag
    $utf8 = 0;
    $encoded_json = MediaWords::Util::JSON::encode_json( $object, $pretty, $utf8 );
    is( $encoded_json, $expected_json, 'encode_json() without UTF-8 flag' );
    $decoded_json = MediaWords::Util::JSON::decode_json( $encoded_json, $utf8 );
    cmp_deeply( $decoded_json, $object, 'decode_json() without UTF-8 flag' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_encode_decode_json();
}

main();
