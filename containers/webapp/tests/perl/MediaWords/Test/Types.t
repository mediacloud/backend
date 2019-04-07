use strict;
use warnings;

use Test::More;
use MediaWords::Test::Types;

sub test_is_integer()
{
    ok( MediaWords::Test::Types::_is_integer( 11111 ) );
    ok( MediaWords::Test::Types::_is_integer( 0 ) );
    ok( MediaWords::Test::Types::_is_integer( -1 ) );

    ok( !MediaWords::Test::Types::_is_integer( undef ) );
    ok( !MediaWords::Test::Types::_is_integer( '' ) );
    ok( !MediaWords::Test::Types::_is_integer( 'string' ) );
    ok( !MediaWords::Test::Types::_is_integer( '11111' ) );
    ok( !MediaWords::Test::Types::_is_integer( 2.7 ) );
}

sub main()
{
    plan tests => 8;

    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_is_integer();
}

main();
