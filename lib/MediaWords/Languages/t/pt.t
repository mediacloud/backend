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
use Test::More tests => 4 + 1;
use utf8;

use MediaWords::Languages::pt;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::pt->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
França (em francês: France; AFI: [fʁɑ̃s] ouça), oficialmente República Francesa (em francês:
République française; [ʁepyblik fʁɑ̃sɛz]) é um país localizado na Europa Ocidental, com várias
ilhas e territórios ultramarinos noutros continentes. A França Metropolitana se estende do
Mediterrâneo ao Canal da Mancha e Mar do Norte, e do Rio Reno ao Oceano Atlântico. É muitas
vezes referida como L'Hexagone ("O Hexágono") por causa da forma geométrica do seu território.
A nação é o maior país da União Europeia em área e o terceiro maior da Europa, atrás apenas da
Rússia e da Ucrânia (incluindo seus territórios extraeuropeus, como a Guiana Francesa, o país
torna-se maior que a Ucrânia).
QUOTE

    $expected_sentences = [
'França (em francês: France; AFI: [fʁɑ̃s] ouça), oficialmente República Francesa (em francês: République française; [ʁepyblik fʁɑ̃sɛz]) é um país localizado na Europa Ocidental, com várias ilhas e territórios ultramarinos noutros continentes.',
'A França Metropolitana se estende do Mediterrâneo ao Canal da Mancha e Mar do Norte, e do Rio Reno ao Oceano Atlântico.',
        'É muitas vezes referida como L\'Hexagone ("O Hexágono") por causa da forma geométrica do seu território.',
'A nação é o maior país da União Europeia em área e o terceiro maior da Europa, atrás apenas da Rússia e da Ucrânia (incluindo seus territórios extraeuropeus, como a Guiana Francesa, o país torna-se maior que a Ucrânia).'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Period in the middle of the number ("1:26.250")
    #
    $test_string = <<'QUOTE';
O Grande Prêmio da Espanha de 2012 foi a quinta corrida da temporada de 2012 da Fórmula 1. A
prova foi disputada no dia 13 de maio no Circuito da Catalunha, em Barcelona, com treino de
classificação no sábado dia 12 de maio. O primeiro treino livre de sexta-feira teve Fernando
Alonso como líder, já a segunda sessão do mesmo dia foi liderado por Jenson Button. No dia
seguinte, a terceira sessão foi dominada por Sebastian Vettel. O pole position havia sido
Lewis Hamilton, entretanto, o piloto inglês foi punido, sendo excluído do classificatório.
Quem herdou a pole position foi o venezuelano Pastor Maldonado, tornando-se o primeiro
venezuelano na história a conquistar a posição de honra na categoria. Maldonado veio a vencer
a prova no dia seguinte e tornou-se também o primeiro venezuelano na história a vencer uma
corrida de Formula 1. O pódio foi completado por Fernando Alonso, da Ferrari, e Kimi Raikkonen,
da Lotus. A volta mais rápida da corrida foi feita pelo francês Romain Grosjean da Lotus com
o tempo de 1:26.250.
QUOTE

    $expected_sentences = [
        'O Grande Prêmio da Espanha de 2012 foi a quinta corrida da temporada de 2012 da Fórmula 1.',
'A prova foi disputada no dia 13 de maio no Circuito da Catalunha, em Barcelona, com treino de classificação no sábado dia 12 de maio.',
'O primeiro treino livre de sexta-feira teve Fernando Alonso como líder, já a segunda sessão do mesmo dia foi liderado por Jenson Button.',
        'No dia seguinte, a terceira sessão foi dominada por Sebastian Vettel.',
'O pole position havia sido Lewis Hamilton, entretanto, o piloto inglês foi punido, sendo excluído do classificatório.',
'Quem herdou a pole position foi o venezuelano Pastor Maldonado, tornando-se o primeiro venezuelano na história a conquistar a posição de honra na categoria.',
'Maldonado veio a vencer a prova no dia seguinte e tornou-se também o primeiro venezuelano na história a vencer uma corrida de Formula 1.',
        'O pódio foi completado por Fernando Alonso, da Ferrari, e Kimi Raikkonen, da Lotus.',
        'A volta mais rápida da corrida foi feita pelo francês Romain Grosjean da Lotus com o tempo de 1:26.250.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviation ("a.C.") with an end-of-sentence period
    #
    $test_string = <<'QUOTE';
Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C..
QUOTE

    $expected_sentences = [ 'Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C..' ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviation ("a.C.") with an end-of-sentence period, plus another sentence
    #
    $test_string = <<'QUOTE';
Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C.. This is a test.
QUOTE

    $expected_sentences = [ 'Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C..', 'This is a test.' ];

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

