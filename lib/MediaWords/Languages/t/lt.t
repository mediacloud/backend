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

use MediaWords::Languages::lt;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::lt->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Kinijos civilizacija yra viena seniausių pasaulyje. Kinijos istorija pasižymi gausa įvairių
rašytinių šaltinių, kurie, kartu su archeologiniais duomenimis, leidžia rekonstruoti
politinį Kinijos gyvenimą ir socialius procesus pradedant gilia senove. Politiškai Kinija
per keletą tūkstantmečių keletą kartų perėjo per besikartojančius politinės vienybės ir
susiskaidymo ciklus. Kinijos teritoriją reguliariai užkariaudavo ateiviai iš išorės, tačiau
daugelis jų anksčiau ar vėliau buvo asimiliuojami į kinų etnosą.
QUOTE

    $expected_sentences = [
        'Kinijos civilizacija yra viena seniausių pasaulyje.',
'Kinijos istorija pasižymi gausa įvairių rašytinių šaltinių, kurie, kartu su archeologiniais duomenimis, leidžia rekonstruoti politinį Kinijos gyvenimą ir socialius procesus pradedant gilia senove.',
'Politiškai Kinija per keletą tūkstantmečių keletą kartų perėjo per besikartojančius politinės vienybės ir susiskaidymo ciklus.',
'Kinijos teritoriją reguliariai užkariaudavo ateiviai iš išorės, tačiau daugelis jų anksčiau ar vėliau buvo asimiliuojami į kinų etnosą.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviated name ("S. Daukanto")
    #
    $test_string = <<'QUOTE';
Lenkimų senosios kapinės, Pušų kapai, Maro kapeliai, Kapeliai (saugotinas kultūros paveldo
objektas) – neveikiančios kapinės vakariniame Skuodo rajono savivaldybės teritorijos
pakraštyje, 1,9 km į rytus nuo Šventosios upės ir Latvijos sienos, Lenkimų miestelio
(Lenkimų seniūnija) pietvakariniame pakraštyje, kelio Skuodas–Kretinga (S. Daukanto
gatvės) dešinėje pusėje. Įrengtos šiaurės – pietų kryptimi pailgoje kalvelėje, apjuostos
statinių tvoros, kurios rytinėje pusėje įrengti varteliai. Kapinių pakraščiuose auga kelios
pušys, o centrinėje dalyje – vietinės reikšmės gamtos paminklu laikoma Kapų pušis. Į pietus
nuo jos stovi monumentalus kryžius ir pora koplytėlių. Pietinėje dalyje išliko pora betoninių
antkapių, ženklinančių buvusius kapus. Priešais kapines pakelėje pastatytas stogastulpio
tipo anotacinis ženklas su įrašu „PUŠŲ KAPAI“. Teritorijos plotas – 0,06 ha.
QUOTE

    $expected_sentences = [
'Lenkimų senosios kapinės, Pušų kapai, Maro kapeliai, Kapeliai (saugotinas kultūros paveldo objektas) – neveikiančios kapinės vakariniame Skuodo rajono savivaldybės teritorijos pakraštyje, 1,9 km į rytus nuo Šventosios upės ir Latvijos sienos, Lenkimų miestelio (Lenkimų seniūnija) pietvakariniame pakraštyje, kelio Skuodas–Kretinga (S. Daukanto gatvės) dešinėje pusėje.',
'Įrengtos šiaurės – pietų kryptimi pailgoje kalvelėje, apjuostos statinių tvoros, kurios rytinėje pusėje įrengti varteliai.',
'Kapinių pakraščiuose auga kelios pušys, o centrinėje dalyje – vietinės reikšmės gamtos paminklu laikoma Kapų pušis.',
        'Į pietus nuo jos stovi monumentalus kryžius ir pora koplytėlių.',
        'Pietinėje dalyje išliko pora betoninių antkapių, ženklinančių buvusius kapus.',
        'Priešais kapines pakelėje pastatytas stogastulpio tipo anotacinis ženklas su įrašu „PUŠŲ KAPAI“.',
        'Teritorijos plotas – 0,06 ha.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Date ("1338 m. rugpjūčio 14 d."), abbreviation ("vok.")
    #
    $test_string = <<'QUOTE';
Galialaukių mūšis – 1338 m. rugpjūčio 14 d. netoli Ragainės pilies vykusios kautynės tarp
LDK ir Vokiečių ordino kariuomenių. Ordino maršalo Heinricho Dusmerio vadovaujami
kryžiuočiai Galialaukių vietovėje (vok. Galelouken, Galelauken) pastojo kelią lietuviams,
grįžtantiems į Lietuvą po trijų dienų niokojamo žygio į Prūsiją, surengto greičiausiai
keršijant ordinui už Bajerburgo pilies pastatymą bei Medininkų valsčiaus nuniokojimą.
QUOTE

    $expected_sentences = [
'Galialaukių mūšis – 1338 m. rugpjūčio 14 d. netoli Ragainės pilies vykusios kautynės tarp LDK ir Vokiečių ordino kariuomenių.',
'Ordino maršalo Heinricho Dusmerio vadovaujami kryžiuočiai Galialaukių vietovėje (vok. Galelouken, Galelauken) pastojo kelią lietuviams, grįžtantiems į Lietuvą po trijų dienų niokojamo žygio į Prūsiją, surengto greičiausiai keršijant ordinui už Bajerburgo pilies pastatymą bei Medininkų valsčiaus nuniokojimą.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Dates ("II tūkst. pr. m. e." and others), abbreviation ("kin.")
    #
    $test_string = <<'QUOTE';
Daugiausia žinių yra išlikę apie Geltonosios upės vidurupio (taip vadinamos Vidurio lygumos)
arealo raidą, kur jau II tūkst. pr. m. e. viduryje į valdžią atėjo pusiau legendinė Šia
dinastija, kurią pakeitė Šangų dinastija. XI a. pr. m. e. čia įsigalėjo Džou dinastija.
Tuo metu Vidurio lygumos karalystė pradėta vadinti tiesiog "Vidurio karalyste" (kin.
Zhongguo), kas ir davė pavadinimą visai Kinijai. Valdant Džou dinastijai, jos monarchų
simbolinis autoritetas išplito po didžiulę teritoriją. Nors atskiros Kinijos valstybės kovojo
tarpusavyje, kultūriniai mainai intensyvėjo, kas ilgainiui vedė į politinį suvienijimą
III a. pr. m. e.
QUOTE

    $expected_sentences = [
'Daugiausia žinių yra išlikę apie Geltonosios upės vidurupio (taip vadinamos Vidurio lygumos) arealo raidą, kur jau II tūkst. pr. m. e. viduryje į valdžią atėjo pusiau legendinė Šia dinastija, kurią pakeitė Šangų dinastija.',
        'XI a. pr. m. e. čia įsigalėjo Džou dinastija.',
'Tuo metu Vidurio lygumos karalystė pradėta vadinti tiesiog "Vidurio karalyste" (kin. Zhongguo), kas ir davė pavadinimą visai Kinijai.',
        'Valdant Džou dinastijai, jos monarchų simbolinis autoritetas išplito po didžiulę teritoriją.',
'Nors atskiros Kinijos valstybės kovojo tarpusavyje, kultūriniai mainai intensyvėjo, kas ilgainiui vedė į politinį suvienijimą III a. pr. m. e.'
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
