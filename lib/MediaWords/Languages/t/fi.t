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

use MediaWords::Languages::fi;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::fi->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Pallokalat (Tetraodontidae) on kalaheimo, johon kuuluu sekä koralliriutoilla, murtovedessä että makeassa
vedessä eläviä lajeja. Vuonna 2004 heimosta tunnettiin 187 lajia, joista jotkut elävät makeassa tai
murtovedessä, jotkut taas viettävät osan elämästään murto- ja osan merivedessä. Pallokalat ovat
saaneet nimensä siitä, että pelästyessään ne imevät itsensä täyteen vettä tai ilmaa ja pullistuvat
palloiksi. Toinen pullistelevien kalojen heimo on siilikalat. Pallokalat ovat terävähampaisia petoja,
jotka syövät muun muassa simpukoita, kotiloita ja muita kaloja. Pallokaloja voidaan pitää akvaariossa,
mutta hoitajan tulee olla perehtynyt niiden hoitoon hyvin.
QUOTE

    $expected_sentences = [
'Pallokalat (Tetraodontidae) on kalaheimo, johon kuuluu sekä koralliriutoilla, murtovedessä että makeassa vedessä eläviä lajeja.',
'Vuonna 2004 heimosta tunnettiin 187 lajia, joista jotkut elävät makeassa tai murtovedessä, jotkut taas viettävät osan elämästään murto- ja osan merivedessä.',
'Pallokalat ovat saaneet nimensä siitä, että pelästyessään ne imevät itsensä täyteen vettä tai ilmaa ja pullistuvat palloiksi.',
        'Toinen pullistelevien kalojen heimo on siilikalat.',
        'Pallokalat ovat terävähampaisia petoja, jotka syövät muun muassa simpukoita, kotiloita ja muita kaloja.',
        'Pallokaloja voidaan pitää akvaariossa, mutta hoitajan tulee olla perehtynyt niiden hoitoon hyvin.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Number followed by a period
    #
    $test_string = <<'QUOTE';
Katso Teiniäidit-sarjan 8. jakso ennakkoon.
QUOTE

    $expected_sentences = [ 'Katso Teiniäidit-sarjan 8. jakso ennakkoon.', ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Dates with a period ("31. tammikuuta", "1. helmikuuta")
    #
    $test_string = <<'QUOTE';
Toisin kuin monissa muissa palkinnoissa, Nobel-palkinnon saajan valitseminen on pitkä prosessi.
Tämä on nostanut palkinnon arvokkuutta ja sen takia palkintoa pidetään alansa arvostetuimpana.
Nobel-komiteat lähettävät vuosittain tuhansille eri alojen tiedemiehille, eri organisaatioiden
ja akatemioiden jäsenille sekä edellisille Nobel-palkinnon saaneille viestin, jossa heitä
pyydetään asettamaan ehdokas seuraavaksi palkinnon saajaksi. Ehdolleasettajat pyritään
valitsemaan siten, että mahdollisimman monet yliopistot ympäri maailmaa saavat asettaa
ehdokkaita mahdollisimman tasa-arvoisesti. Vuosittain ehdolle asetetaan 200–300 henkilöä
(myös joitakin organisaatioita voidaan ehdottaa) kuhunkin palkintoryhmään. Ehdokkaita ei saa
julkistaa ennen kuin 50 vuotta on kulunut ehdolle asettumisen jälkeen. Aikaraja ehdotusten
lähettämiseen on 31. tammikuuta. Rauhanpalkinnon aikaraja on 1. helmikuuta.
QUOTE

    $expected_sentences = [
        'Toisin kuin monissa muissa palkinnoissa, Nobel-palkinnon saajan valitseminen on pitkä prosessi.',
        'Tämä on nostanut palkinnon arvokkuutta ja sen takia palkintoa pidetään alansa arvostetuimpana.',
'Nobel-komiteat lähettävät vuosittain tuhansille eri alojen tiedemiehille, eri organisaatioiden ja akatemioiden jäsenille sekä edellisille Nobel-palkinnon saaneille viestin, jossa heitä pyydetään asettamaan ehdokas seuraavaksi palkinnon saajaksi.',
'Ehdolleasettajat pyritään valitsemaan siten, että mahdollisimman monet yliopistot ympäri maailmaa saavat asettaa ehdokkaita mahdollisimman tasa-arvoisesti.',
'Vuosittain ehdolle asetetaan 200–300 henkilöä (myös joitakin organisaatioita voidaan ehdottaa) kuhunkin palkintoryhmään.',
        'Ehdokkaita ei saa julkistaa ennen kuin 50 vuotta on kulunut ehdolle asettumisen jälkeen.',
        'Aikaraja ehdotusten lähettämiseen on 31. tammikuuta.',
        'Rauhanpalkinnon aikaraja on 1. helmikuuta.',
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviations, numbers
    #
    $test_string = <<'QUOTE';
Vuotta 0 ei jostakin syystä ole otettu käyttöön juliaanisessa eikä gregoriaanisessa ajanlaskussa,
vaikka normaalisti ajan kulun laskeminen aloitetaan nollasta, kuten kalenterivuorokausi kello 0.00
ja vasta ensimmäisen tunnin kuluttua on kello 1.00. Myös ihmisen syntymästä, jostakin tapahtumasta
tai sen alusta mennyt aika ilmoitetaan ajanlaskun alusta kuluneina täysinä vuosina: kun ensimmäinen
vuosi (vuosi 0) on mennyt, vasta silloin merkitään 1 tai kun kymmenes vuosi (vuosi 9) on kulunut,
on kymmenen vuotta täynnä ja alkaa vuosi 10 alkuhetkestä laskettuna. Ajanlaskun ensimmäisenä
pidetty vuosi on 1 jKr., ja vasta sen päätyttyä oli Kristuksen syntymästä kulunut 1 vuosi.
QUOTE

    $expected_sentences = [
'Vuotta 0 ei jostakin syystä ole otettu käyttöön juliaanisessa eikä gregoriaanisessa ajanlaskussa, vaikka normaalisti ajan kulun laskeminen aloitetaan nollasta, kuten kalenterivuorokausi kello 0.00 ja vasta ensimmäisen tunnin kuluttua on kello 1.00.',
'Myös ihmisen syntymästä, jostakin tapahtumasta tai sen alusta mennyt aika ilmoitetaan ajanlaskun alusta kuluneina täysinä vuosina: kun ensimmäinen vuosi (vuosi 0) on mennyt, vasta silloin merkitään 1 tai kun kymmenes vuosi (vuosi 9) on kulunut, on kymmenen vuotta täynnä ja alkaa vuosi 10 alkuhetkestä laskettuna.',
'Ajanlaskun ensimmäisenä pidetty vuosi on 1 jKr., ja vasta sen päätyttyä oli Kristuksen syntymästä kulunut 1 vuosi.'
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
