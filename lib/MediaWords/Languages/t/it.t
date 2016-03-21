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

use MediaWords::Languages::it;
use Data::Dumper;

sub test_get_sentences()
{

    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::it->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Charles André Joseph Marie de Gaulle (Lilla, 22 novembre 1890 – Colombey-les-deux-Églises, 9 novembre 1970) è
stato un generale e politico francese. Dopo la sua partenza per Londra nel giugno del 1940, divenne il capo
della Francia libera, che ha combattuto contro il regime di Vichy e contro l'occupazione italiana e tedesca
della Francia durante la seconda guerra mondiale. Presidente del governo provvisorio della Repubblica
francese 1944-1946, ultimo presidente del Consiglio (1958-1959) della Quarta Repubblica, è stato il promotore
della fondazione della Quinta Repubblica, della quale fu primo presidente dal 1959-1969.
QUOTE

    $expected_sentences = [
'Charles André Joseph Marie de Gaulle (Lilla, 22 novembre 1890 – Colombey-les-deux-Églises, 9 novembre 1970) è stato un generale e politico francese.',
'Dopo la sua partenza per Londra nel giugno del 1940, divenne il capo della Francia libera, che ha combattuto contro il regime di Vichy e contro l\'occupazione italiana e tedesca della Francia durante la seconda guerra mondiale.',
'Presidente del governo provvisorio della Repubblica francese 1944-1946, ultimo presidente del Consiglio (1958-1959) della Quarta Repubblica, è stato il promotore della fondazione della Quinta Repubblica, della quale fu primo presidente dal 1959-1969.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Period in the middle of the number
    #
    $test_string = <<'QUOTE';
Nel 1964, l'azienda di Berlusconi apre un cantiere a Brugherio per edificare una città modello da 4.000 abitanti.
I primi condomini sono pronti già nel 1965, ma non si vendono con facilità.
QUOTE

    $expected_sentences = [
'Nel 1964, l\'azienda di Berlusconi apre un cantiere a Brugherio per edificare una città modello da 4.000 abitanti.',
        'I primi condomini sono pronti già nel 1965, ma non si vendono con facilità.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Acronym ("c.a.p.")
    #
    $test_string = <<'QUOTE';
La precompressione è una tecnica industriale consistente nel produrre artificialmente una tensione nella
struttura dei materiali da costruzione, e in special modo nel calcestruzzo armato, allo scopo di migliorarne
le caratteristiche di resistenza. Nel calcestruzzo armato precompresso (nel linguaggio comune chiamato
anche cemento armato precompresso, abbreviato con l'acronimo c.a.p.), la precompressione viene
utilizzata per sopperire alla scarsa resistenza a trazione del conglomerato cementizio.
QUOTE

    $expected_sentences = [
'La precompressione è una tecnica industriale consistente nel produrre artificialmente una tensione nella struttura dei materiali da costruzione, e in special modo nel calcestruzzo armato, allo scopo di migliorarne le caratteristiche di resistenza.',
'Nel calcestruzzo armato precompresso (nel linguaggio comune chiamato anche cemento armato precompresso, abbreviato con l\'acronimo c.a.p.), la precompressione viene utilizzata per sopperire alla scarsa resistenza a trazione del conglomerato cementizio.'
    ];

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
