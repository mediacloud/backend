#!/usr/bin/env prove

use strict;
use warnings;
use utf8;

use Test::More tests => 17;
use Test::NoWarnings;
use Test::Deep;

use Readonly;
use Data::Dumper;
use Inline::Python;

use MediaWords::Util::Python;

sub test_python_deep_copy()
{
    my $input = {
        'a' => undef,
        'b' => 1,
        'c' => 'd',
        'e' => [
            'f' => {
                0 => $Inline::Python::Boolean::true,
                1 => $Inline::Python::Boolean::false,
            }
        ],
    };
    my $expected_output = $input;
    my $actual_output   = python_deep_copy( $input );
    cmp_deeply( $actual_output, $expected_output );
    isnt( $input, $actual_output, 'References must be different' );
}

sub test_normalize_boolean_for_db()
{
    my $allow_null;
    $allow_null = 0;
    is( normalize_boolean_for_db( undef, $allow_null ), 'f' );
    $allow_null = 1;
    is( normalize_boolean_for_db( undef, $allow_null ), undef );

    is( normalize_boolean_for_db( 1 ),                              't' );
    is( normalize_boolean_for_db( '1' ),                            't' );
    is( normalize_boolean_for_db( 't' ),                            't' );
    is( normalize_boolean_for_db( 'T' ),                            't' );
    is( normalize_boolean_for_db( 'TRUE' ),                         't' );
    is( normalize_boolean_for_db( $Inline::Python::Boolean::true ), 't' );

    is( normalize_boolean_for_db( 0 ),                               'f' );
    is( normalize_boolean_for_db( '0' ),                             'f' );
    is( normalize_boolean_for_db( 'f' ),                             'f' );
    is( normalize_boolean_for_db( 'F' ),                             'f' );
    is( normalize_boolean_for_db( 'FALSE' ),                         'f' );
    is( normalize_boolean_for_db( $Inline::Python::Boolean::false ), 'f' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_python_deep_copy();
    test_normalize_boolean_for_db();
}

main();
