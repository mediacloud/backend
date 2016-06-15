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
use Test::More tests => 2 + 1;
use utf8;

use MediaWords::Languages::fr;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::fr->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Jusqu'aux années 2000, l'origine du cheval domestique est étudiée par synapomorphie, en comparant
des fossiles et squelettes. Les progrès de la génétique permettent désormais une autre approche,
le nombre de gènes entre les différentes espèces d'équidés étant variable. La différentiation
entre les espèces d’Equus laisse à penser que cette domestication est récente, et qu'elle concerne
un nombre restreint d'étalons pour un grand nombre de juments, capturées à l'état sauvage afin
de repeupler les élevages domestiques. Peu à peu, l'élevage sélectif entraîne une distinction des
chevaux selon leur usage, la traction ou la selle, et un accroissement de la variété des robes de
leurs robes.
QUOTE

    $expected_sentences = [
'Jusqu\'aux années 2000, l\'origine du cheval domestique est étudiée par synapomorphie, en comparant des fossiles et squelettes.',
'Les progrès de la génétique permettent désormais une autre approche, le nombre de gènes entre les différentes espèces d\'équidés étant variable.',
'La différentiation entre les espèces d’Equus laisse à penser que cette domestication est récente, et qu\'elle concerne un nombre restreint d\'étalons pour un grand nombre de juments, capturées à l\'état sauvage afin de repeupler les élevages domestiques.',
'Peu à peu, l\'élevage sélectif entraîne une distinction des chevaux selon leur usage, la traction ou la selle, et un accroissement de la variété des robes de leurs robes.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Non-breakable abbreviation (e.g. "4500 av. J.-C.")
    #
    $test_string = <<'QUOTE';
La domestication du cheval est l'ensemble des processus de domestication conduisant l'homme à
maîtriser puis à utiliser l'espèce Equus caballus (le cheval) à son profit grâce au contrôle
des naissances et à l'élevage de ces animaux pour la consommation, la guerre, le travail et
le transport. De nombreuses théories sont proposées, tant en termes d'époque, de nombre de
foyers de domestication, que de types, espèces ou sous-espèces de chevaux domestiqués. Plus
tardive que pour les espèces animales alimentaires, la domestication du cheval est difficile
à dater avec précision. Les premiers apprivoisements pourraient remonter au Paléolithique
supérieur, 8 000 ans avant notre ère. La première preuve archéologique date de 4500 av. J.-C. dans
les steppes au Nord du Kazakhstan, parmi la culture Botaï. D'autres éléments en évoquent
indépendamment dans la péninsule ibérique, et peut-être la péninsule arabique. Les recherches
précédentes se sont longtemps focalisées sur les steppes d'Asie centrale, vers 4000 à 3500 av. J.-C..
QUOTE

    $expected_sentences = [
'La domestication du cheval est l\'ensemble des processus de domestication conduisant l\'homme à maîtriser puis à utiliser l\'espèce Equus caballus (le cheval) à son profit grâce au contrôle des naissances et à l\'élevage de ces animaux pour la consommation, la guerre, le travail et le transport.',
'De nombreuses théories sont proposées, tant en termes d\'époque, de nombre de foyers de domestication, que de types, espèces ou sous-espèces de chevaux domestiqués.',
'Plus tardive que pour les espèces animales alimentaires, la domestication du cheval est difficile à dater avec précision.',
        'Les premiers apprivoisements pourraient remonter au Paléolithique supérieur, 8 000 ans avant notre ère.',
'La première preuve archéologique date de 4500 av. J.-C. dans les steppes au Nord du Kazakhstan, parmi la culture Botaï.',
'D\'autres éléments en évoquent indépendamment dans la péninsule ibérique, et peut-être la péninsule arabique.',
'Les recherches précédentes se sont longtemps focalisées sur les steppes d\'Asie centrale, vers 4000 à 3500 av. J.-C..'
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
