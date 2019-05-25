use strict;
use warnings;
use utf8;

use Test::NoWarnings;
use Readonly;
use Test::More tests => 17;
use Test::Deep;

use_ok( 'MediaWords::Util::Text' );


sub test_encode_decode_utf8()
{
    Readonly my @test_strings => (

        # ASCII
        "Media Cloud\r\nMedia Cloud\nMedia Cloud\r\n",

        # UTF-8
        "Media Cloud\r\nąčęėįšųūž\n您好\r\n",

        # Empty string
        "",

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
        my $encoded_string = MediaWords::Util::Text::encode_to_utf8( $test_string );
        my $decoded_string = MediaWords::Util::Text::decode_from_utf8( $encoded_string );
        is( $decoded_string, $test_string, "Encoded+decoded string matches" );
    }
}

sub test_recursively_encode_to_utf8()
{
    my $ascii_string       = 'Vazquez';
    my $not_encoded_string = "V\x{00}\x{e1}zquez";
    my $encoded_string     = MediaWords::Util::Text::encode_to_utf8( $not_encoded_string );
    my $not_a_string       = 42;

    my $input = [
        {
            $ascii_string       => $ascii_string,
            $not_encoded_string => $not_encoded_string,
            $not_a_string       => $not_a_string
        },
        [ $ascii_string, $not_encoded_string, $not_a_string, ],
        $ascii_string,
        $not_encoded_string,
        $not_a_string,
    ];

    my $expected_output = [
        {
            $ascii_string   => $ascii_string,
            $encoded_string => $encoded_string,
            $not_a_string   => $not_a_string
        },
        [ $ascii_string, $encoded_string, $not_a_string, ],
        $ascii_string,
        $encoded_string,
        $not_a_string,
    ];

    my $actual_output = MediaWords::Util::Text::recursively_encode_to_utf8( $input );

    cmp_deeply( $actual_output, $expected_output, 'Structure got encoded successfully' );
}

sub test_is_valid_utf8()
{
    ok( MediaWords::Util::Text::is_valid_utf8( 'pnoןɔ ɐıpǝɯ' ), 'Valid UTF-8' );
    ok( !MediaWords::Util::Text::is_valid_utf8( "\xc3\x28" ),         'Invalid UTF-8' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_encode_decode_utf8();
    test_recursively_encode_to_utf8();
    test_is_valid_utf8();
}

main();
