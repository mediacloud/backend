use strict;
use warnings;

use utf8;

use Test::NoWarnings;
use Test::More tests => 30;

use Readonly;

use_ok( 'MediaWords::Util::IdentifyLanguage' );

Readonly my $english_text => 'The quick brown fox jumps over the lazy dog.';
Readonly my $russian_text =>
'«Олл Блэкс» удерживали первую строчку в рейтинге сборных Международного совета регби дольше, чем все остальные команды вместе взятые.';

sub test_language_code_for_text()
{
    is( MediaWords::Util::IdentifyLanguage::language_code_for_text( $english_text ),
        'en', 'English text identified as English' );
    is( MediaWords::Util::IdentifyLanguage::language_code_for_text( $russian_text ),
        'ru', 'Russian text identified as Russian' );

    is( MediaWords::Util::IdentifyLanguage::language_code_for_text( '' ),    '', 'Empty text' );
    is( MediaWords::Util::IdentifyLanguage::language_code_for_text( undef ), '', 'Undefined text' );

    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( '0000000000000000000000' ), 'Digits' );
    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( '000000000000000aaaaaaa' ),
        'More digits than letters' );
}

sub test_identification_would_be_reliable()
{
    ok( MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( $english_text ), 'English text' );
    ok( MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( $russian_text ), 'Russian text' );

    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( undef ), 'Undef text' );
    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( '' ),    'Empty text' );
    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( 'abc' ), 'Too short text' );
    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( '______________________' ), 'Underscores' );
}

sub test_language_is_supported()
{
    ok( MediaWords::Util::IdentifyLanguage::language_is_supported( 'en' ),  'Supported language' );
    ok( !MediaWords::Util::IdentifyLanguage::language_is_supported( 'xx' ), 'Unsupported language' );

    ok( !MediaWords::Util::IdentifyLanguage::language_is_supported( '' ),    'Empty language' );
    ok( !MediaWords::Util::IdentifyLanguage::language_is_supported( undef ), 'Undef language' );
}

sub test_utf8()
{
    Readonly my @test_strings => (

        # UTF-8
        "Media Cloud\r\nąčęėįšųūž\n您好\r\n",

        # Invalid UTF-8 sequences
        "\xc3\x28",
        "\xa0\xa1",
        "\xe2\x28\xa1",
        "\xe2\x82\x28",
        "\xf0\x28\x8c\xbc",
        "\xf0\x90\x28\xbc",
        "\xf0\x28\x8c\x28",
        "\xf8\xa1\xa1\xa1\xa1",
        "\xfc\xa1\xa1\xa1\xa1\xa1",

    );

    foreach my $test_string ( @test_strings )
    {
        eval { MediaWords::Util::IdentifyLanguage::language_code_for_text( $test_string ); };
        ok( !$@, "UTF-8 string: $test_string" );
    }
}

sub test_very_long_string()
{
    my $very_long_string = 'a' x ( 1024 * 1024 * 10 );    # 10 MB of 'a'
    ok( length( $very_long_string ) > 1024 * 1024 * 9 );
    eval { MediaWords::Util::IdentifyLanguage::language_code_for_text( $very_long_string ); };
    ok( !$@, "Very long string" );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ':utf8';
    binmode $builder->failure_output, ':utf8';
    binmode $builder->todo_output,    ':utf8';

    test_language_code_for_text();
    test_identification_would_be_reliable();
    test_language_is_supported();
    test_utf8();
    test_very_long_string();
}

main();
