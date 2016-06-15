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

use MediaWords::Languages::ro;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::ro->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
În prezent, din întreg ansamblul mănăstirii s-a mai păstrat doar biserica și o clopotniță.
Acestea se află amplasate pe strada Sapienței din sectorul 5 al municipiului București,
în spatele unor blocuri construite în timpul regimului comunist, din apropierea Splaiului
Independenței și a parcului Izvor. În 1813 Mănăstirea Mihai-Vodă „era printre mănăstirile
mari ale țării”.
QUOTE

    $expected_sentences = [
        'În prezent, din întreg ansamblul mănăstirii s-a mai păstrat doar biserica și o clopotniță.',
'Acestea se află amplasate pe strada Sapienței din sectorul 5 al municipiului București, în spatele unor blocuri construite în timpul regimului comunist, din apropierea Splaiului Independenței și a parcului Izvor.',
        'În 1813 Mănăstirea Mihai-Vodă „era printre mănăstirile mari ale țării”.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Names ("Sf. Mc. Trifon" and others)
    #
    $test_string = <<'QUOTE';
În prezent în interiorul bisericii există o raclă în care sunt păstrate moștele
următorilor Sfinți: Sf. Ioan Iacob Hozevitul, Sf. Xenia Petrovna, Sf. Teofil, Sf. Mc.
Sevastiana, Sf. Mc. Ciprian, Sf. Mc. Iustina, Sf. Mc. Clement, Sf. Mc. Trifon, Cuv.
Auxenție, Sf. Dionisie Zakynthos, Sf. Mc. Anastasie, Sf. Mc. Panaghiotis, Sf. Spiridon,
Sf. Nifon II, Sf. Ignatie Zagorski, Sf. Prooroc Ioan Botezătorul, Cuv. Sava cel Sfințit,
Sf. Mc. Eustatie, Sf. Mc. Theodor Stratilat, Cuv. Paisie, Cuv. Stelian Paflagonul, Sf.
Mc. Mercurie, Sf. Mc. Arhidiacon Ștefan, Sf. Apostol Andrei, Sf. Mc. Dimitrie, Sf. Mc.
Haralambie.
QUOTE

    $expected_sentences = [
'În prezent în interiorul bisericii există o raclă în care sunt păstrate moștele următorilor Sfinți: Sf. Ioan Iacob Hozevitul, Sf. Xenia Petrovna, Sf. Teofil, Sf. Mc. Sevastiana, Sf. Mc. Ciprian, Sf. Mc. Iustina, Sf. Mc. Clement, Sf. Mc. Trifon, Cuv. Auxenție, Sf. Dionisie Zakynthos, Sf. Mc. Anastasie, Sf. Mc. Panaghiotis, Sf. Spiridon, Sf. Nifon II, Sf. Ignatie Zagorski, Sf. Prooroc Ioan Botezătorul, Cuv. Sava cel Sfințit, Sf. Mc. Eustatie, Sf. Mc. Theodor Stratilat, Cuv. Paisie, Cuv. Stelian Paflagonul, Sf. Mc. Mercurie, Sf. Mc. Arhidiacon Ștefan, Sf. Apostol Andrei, Sf. Mc. Dimitrie, Sf. Mc. Haralambie.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviation ("nr.4")
    #
    $test_string = <<'QUOTE';
Translatarea în pantă a bisericii, pe o distanță de 289 m și coborâtă pe verticală cu
6,2 m, a avut loc în anul 1985. Operațiune în sine de translatare a edificiului, de
pe Dealul Mihai Vodă, fosta stradă a Arhivelor nr.2 și până în locul în care se află și
astăzi, Strada Sapienței nr.4, în apropierea malului Dâmboviței, a fost considerată la
vremea respectivă o performanță deosebită.
QUOTE

    $expected_sentences = [
'Translatarea în pantă a bisericii, pe o distanță de 289 m și coborâtă pe verticală cu 6,2 m, a avut loc în anul 1985.',
'Operațiune în sine de translatare a edificiului, de pe Dealul Mihai Vodă, fosta stradă a Arhivelor nr.2 și până în locul în care se află și astăzi, Strada Sapienței nr.4, în apropierea malului Dâmboviței, a fost considerată la vremea respectivă o performanță deosebită.'
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
