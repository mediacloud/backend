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

use MediaWords::Languages::sv;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::sv->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
I sin ungdom studerade Lutosławski piano och komposition i Warszawa. Hans tidiga verk var påverkade av
polsk folkmusik. Han började utveckla sin karaktäristiska kompositionsteknik i slutet av 1950-talet.
Musiken från den här perioden och framåt inbegriper en egen metod att bygga harmonier av mindre grupper
av intervall. Den använder också slumpmässiga processer i vilka stämmornas rytmiska samordning inbegriper
ett moment av slumpmässighet. Hans kompositioner omfattar fyra symfonier, en konsert för orkester, flera
konserter för solo och orkester och orkestrala sångcykler. Efter andra världskriget bannlyste de
stalinistiska makthavarna hans kompositioner då de uppfattades som formalistiska och därmed tillgängliga
bara för en insatt elit, medan Lutosławski själv alltid motsatte sig den socialistiska realismen. Under
1980-talet utnyttjade Lutosławski sin internationella ryktbarhet för att stödja Solidaritet.
QUOTE

    $expected_sentences = [
        'I sin ungdom studerade Lutosławski piano och komposition i Warszawa.',
        'Hans tidiga verk var påverkade av polsk folkmusik.',
        'Han började utveckla sin karaktäristiska kompositionsteknik i slutet av 1950-talet.',
'Musiken från den här perioden och framåt inbegriper en egen metod att bygga harmonier av mindre grupper av intervall.',
'Den använder också slumpmässiga processer i vilka stämmornas rytmiska samordning inbegriper ett moment av slumpmässighet.',
'Hans kompositioner omfattar fyra symfonier, en konsert för orkester, flera konserter för solo och orkester och orkestrala sångcykler.',
'Efter andra världskriget bannlyste de stalinistiska makthavarna hans kompositioner då de uppfattades som formalistiska och därmed tillgängliga bara för en insatt elit, medan Lutosławski själv alltid motsatte sig den socialistiska realismen.',
        'Under 1980-talet utnyttjade Lutosławski sin internationella ryktbarhet för att stödja Solidaritet.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviations ("f. Kr.", "a.C.n.", "A. D.")
    #
    $test_string = <<'QUOTE';
Efter Kristus (förkortat e. Kr.) är den i modern svenska vanligtvis använda benämningen på Anno Domini
(latin för Herrens år), utförligare Anno Domini Nostri Iesu Christi (i vår Herres Jesu Kristi år),
oftast förkortat A. D. eller AD, vilket har varit den dominerande tideräkningsnumreringen av årtal i
modern tid i Europa. Årtalssystemet används fortfarande i hela västvärlden och i vetenskapliga och
kommersiella sammanhang även i resten av världen, när man anser att "efter" behöver förtydligas. Efter
den Gregorianska kalenderns införande har bruket att sätta ut AD vid årtalet stadigt minskat.
QUOTE

    $expected_sentences = [
'Efter Kristus (förkortat e. Kr.) är den i modern svenska vanligtvis använda benämningen på Anno Domini (latin för Herrens år), utförligare Anno Domini Nostri Iesu Christi (i vår Herres Jesu Kristi år), oftast förkortat A. D. eller AD, vilket har varit den dominerande tideräkningsnumreringen av årtal i modern tid i Europa.',
'Årtalssystemet används fortfarande i hela västvärlden och i vetenskapliga och kommersiella sammanhang även i resten av världen, när man anser att "efter" behöver förtydligas.',
        'Efter den Gregorianska kalenderns införande har bruket att sätta ut AD vid årtalet stadigt minskat.'
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
