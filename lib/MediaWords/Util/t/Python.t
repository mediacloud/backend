use strict;
use warnings;
use utf8;

use Test::More tests => 3;
use Test::NoWarnings;
use Test::Deep;

use Readonly;
use Data::Dumper;
use Inline::Python;

use MediaWords::Util::Python;

sub test_make_python_variable_writable()
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
    my $actual_output   = make_python_variable_writable( $input );
    cmp_deeply( $actual_output, $expected_output );
    isnt( $input, $actual_output, 'References must be different' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_make_python_variable_writable();
}

main();
