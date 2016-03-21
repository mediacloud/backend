#!/usr/bin/perl
#
# Some test strings copied from Wikipedia (CC-BY-SA, http://creativecommons.org/licenses/by-sa/3.0/).
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 3 + 1;
use utf8;

use MediaWords::Languages::no;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::no->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Tuvalu er en øynasjon i Polynesia i Stillehavet. Landet har i overkant av 10 000 innbyggere,
og er dermed den selvstendige staten i verden med tredje færrest innbyggere, etter
Vatikanstaten og Nauru. Tuvalu består av ni bebodde atoller spredt over et havområde på
rundt 1,3 millioner km². Med et landareal på bare 26 km² er det verdens fjerde minste
uavhengige stat. De nærmeste øygruppene er Kiribati, Nauru, Samoa og Fiji.
QUOTE

    $expected_sentences = [
        'Tuvalu er en øynasjon i Polynesia i Stillehavet.',
'Landet har i overkant av 10 000 innbyggere, og er dermed den selvstendige staten i verden med tredje færrest innbyggere, etter Vatikanstaten og Nauru.',
        'Tuvalu består av ni bebodde atoller spredt over et havområde på rundt 1,3 millioner km².',
        'Med et landareal på bare 26 km² er det verdens fjerde minste uavhengige stat.',
        'De nærmeste øygruppene er Kiribati, Nauru, Samoa og Fiji.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Date ("1. oktober 1978")
    #
    $test_string = <<'QUOTE';
De første innbyggerne på Tuvalu var polynesiske folk. Den spanske oppdageren Álvaro de
Mendaña ble i 1568 den første europeeren som fikk øye på landet. I 1819 fikk det navnet
Elliceøyene. Det kom under britisk innflytelse på slutten av 1800-tallet, og fra 1892
til 1976 utgjorde det en del av det britiske protektoratet og kolonien Gilbert- og
Elliceøyene, sammen med en del av dagens Kiribati. Tuvalu ble selvstendig 1. oktober 1978.
QUOTE

    $expected_sentences = [
        'De første innbyggerne på Tuvalu var polynesiske folk.',
        'Den spanske oppdageren Álvaro de Mendaña ble i 1568 den første europeeren som fikk øye på landet.',
        'I 1819 fikk det navnet Elliceøyene.',
'Det kom under britisk innflytelse på slutten av 1800-tallet, og fra 1892 til 1976 utgjorde det en del av det britiske protektoratet og kolonien Gilbert- og Elliceøyene, sammen med en del av dagens Kiribati.',
        'Tuvalu ble selvstendig 1. oktober 1978.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviation
    #
    $test_string = <<'QUOTE';
Tettest er den på hovedatollen Funafuti, med over 1000 innb./km².
QUOTE

    $expected_sentences = [ 'Tettest er den på hovedatollen Funafuti, med over 1000 innb./km².' ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_get_sentences();
}

main();
