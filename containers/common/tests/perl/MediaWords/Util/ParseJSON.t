#!/usr/bin/env prove

use strict;
use warnings;
use utf8;

use Test::NoWarnings;
use Readonly;
use Test::More tests => 8;
use Test::Deep;
use Data::Dumper;

use_ok( 'MediaWords::Util::ParseJSON' );

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

    my $pretty = 0;
    my ( $encoded_json, $decoded_json );

    $encoded_json = MediaWords::Util::ParseJSON::encode_json( $object, $pretty );
    is( $encoded_json, $expected_json, 'encode_json()' );
    $decoded_json = MediaWords::Util::ParseJSON::decode_json( $encoded_json );
    cmp_deeply( $decoded_json, $object, 'decode_json()' );

    # Encoding errors
    eval { MediaWords::Util::ParseJSON::encode_json( undef ); };
    ok( $@, 'Trying to encode undefined JSON' );
    eval { MediaWords::Util::ParseJSON::encode_json( "strings can't be encoded" ); };
    ok( $@, 'Trying to encode a string' );

    eval { MediaWords::Util::ParseJSON::decode_json( undef ); };
    ok( $@, 'Trying to decode undefined JSON' );
    eval { MediaWords::Util::ParseJSON::decode_json( 'not JSON' ); };
    ok( $@, 'Trying to decode invalid JSON' );
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
