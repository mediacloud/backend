use strict;
use warnings;

use Test::NoWarnings;
use Test::More tests => 13;

use MediaWords::Languages::Language;

use Data::Dumper;

sub test_language_is_enabled()
{
    ok( MediaWords::Languages::Language::language_is_enabled( 'en' ) );
    ok( MediaWords::Languages::Language::language_is_enabled( 'lt' ) );

    ok( !MediaWords::Languages::Language::language_is_enabled( undef ) );
    ok( !MediaWords::Languages::Language::language_is_enabled( '' ) );
    ok( !MediaWords::Languages::Language::language_is_enabled( 'xx' ) );
}

sub test_language_for_code()
{
    my $en = MediaWords::Languages::Language::language_for_code( 'en' );
    is( $en->language_code(), 'en' );

    my $lt = MediaWords::Languages::Language::language_for_code( 'lt' );
    is( $lt->language_code(), 'lt' );

    is( MediaWords::Languages::Language::language_for_code( undef ), undef );
    is( MediaWords::Languages::Language::language_for_code( '' ),    undef );
    is( MediaWords::Languages::Language::language_for_code( 'xx' ),  undef );
}

sub test_default_language_code()
{
    is( MediaWords::Languages::Language::default_language_code(), 'en' );
}

sub test_default_language()
{
    my $default_lang = MediaWords::Languages::Language::default_language();
    is( $default_lang->language_code(), 'en' );
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_language_is_enabled();
    test_language_for_code();
    test_default_language_code();
    test_default_language();
}

main();
