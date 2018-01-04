#!/usr/bin/perl
#
# Some test strings copied from Wikipedia (CC-BY-SA, http://creativecommons.org/licenses/by-sa/3.0/).
#

use strict;
use warnings;

use Readonly;

use Test::NoWarnings;
use Test::More tests => 4;
use utf8;

use MediaWords::Languages::ca;
use Data::Dumper;

sub test_split_text_to_sentences()
{
    my $lang = MediaWords::Languages::ca->new();

    my $test_string = <<'QUOTE';
El Palau de la Música Catalana és un auditori de música situat al barri de Sant
Pere (Sant Pere, Santa Caterina i la Ribera) de Barcelona. Va ser projectat per
l'arquitecte barceloní Lluís Domènech i Montaner, un dels màxims representants
del modernisme català.
QUOTE

    my $expected_sentences = [
"El Palau de la Música Catalana és un auditori de música situat al barri de Sant Pere (Sant Pere, Santa Caterina i la Ribera) de Barcelona.",
"Va ser projectat per l'arquitecte barceloní Lluís Domènech i Montaner, un dels màxims representants del modernisme català.",
    ];

    is( join( '||', @{ $lang->split_text_to_sentences( $test_string ) } ), join( '||', @{ $expected_sentences } ) );
}

sub test_tokenize()
{
    my $lang = MediaWords::Languages::ca->new();

    my $input_string =
"Després del Brexit, es confirma el trasllat de l'Agència Europea de Medicaments i l'Autoritat Bancària Europea a Amsterdam i París, respectivament.";
    my $expected_words = [
        "després", "del",         "brexit",     "es",      "confirma", "el",
        "trasllat", "de",          "l'agència", "europea", "de",       "medicaments",
        "i",        "l'autoritat", "bancària",  "europea", "a",        "amsterdam",
        "i",        "parís",      "respectivament"
    ];
    is_deeply( $lang->split_sentence_to_words( $input_string ), $expected_words );
}

sub test_stem()
{
    my $lang = MediaWords::Languages::ca->new();

    is_deeply( $lang->stem_words( [ qw/El Palau de la Música Catalana/ ] ), [ qw/ el pal de la music catal / ] );
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_split_text_to_sentences();
    test_tokenize();
    test_stem();
}

main();
