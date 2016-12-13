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

use MediaWords::Languages::es;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::es->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
El paracetamol (DCI) o acetaminofén (acetaminofeno) es un fármaco con propiedades analgésicas,
sin propiedades antiinflamatorias clínicamente significativas. Actúa inhibiendo la síntesis de
prostaglandinas, mediadores celulares responsables de la aparición del dolor. Además, tiene
efectos antipiréticos. Se presenta habitualmente en forma de cápsulas, comprimidos, supositorios
o gotas de administración oral.
QUOTE

    $expected_sentences = [
'El paracetamol (DCI) o acetaminofén (acetaminofeno) es un fármaco con propiedades analgésicas, sin propiedades antiinflamatorias clínicamente significativas.',
        'Actúa inhibiendo la síntesis de prostaglandinas, mediadores celulares responsables de la aparición del dolor.',
        'Además, tiene efectos antipiréticos.',
        'Se presenta habitualmente en forma de cápsulas, comprimidos, supositorios o gotas de administración oral.'
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
Esa misma noche el ministro de Defensa, Ehud Barak, consiguió el apoyo del gabinete israelí para ampliar
la movilización de reservistas de 30.000 a 75.000, de cara a una posible operación terrestre sobre la
Franja de Gaza. El ministro de Relaciones Exteriores Avigdor Lieberman, aclaró que el gobierno actual
no estaba considerando el derrocamiento del gobierno de Hamas en la Franja, y que lo tendría que decidir
el próximo gobierno.
QUOTE

    $expected_sentences = [
'Esa misma noche el ministro de Defensa, Ehud Barak, consiguió el apoyo del gabinete israelí para ampliar la movilización de reservistas de 30.000 a 75.000, de cara a una posible operación terrestre sobre la Franja de Gaza.',
'El ministro de Relaciones Exteriores Avigdor Lieberman, aclaró que el gobierno actual no estaba considerando el derrocamiento del gobierno de Hamas en la Franja, y que lo tendría que decidir el próximo gobierno.',
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
