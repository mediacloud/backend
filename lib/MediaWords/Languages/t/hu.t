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
use Test::More tests => 9 + 1;
use utf8;

use MediaWords::Languages::hu;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::hu->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Ifjúkoráról keveset tudni, a kor igényeinek megfelelően valószínűleg matematikát és hajózást tanult.
Miután Kolumbusz Kristóf spanyol zászló alatt hajózva felfedezte Amerikát 1492-ben, Portugália joggal
érezhette, hogy lépéshátrányba került nagy riválisával szemben. Öt esztendővel később a lisszaboni
kikötőből kifutott az első olyan flotta, amelyik Indiába akart eljutni azon az útvonalon, amelyet
Bartolomeu Dias megnyitott a portugálok számára.
QUOTE

    $expected_sentences = [
        'Ifjúkoráról keveset tudni, a kor igényeinek megfelelően valószínűleg matematikát és hajózást tanult.',
'Miután Kolumbusz Kristóf spanyol zászló alatt hajózva felfedezte Amerikát 1492-ben, Portugália joggal érezhette, hogy lépéshátrányba került nagy riválisával szemben.',
'Öt esztendővel később a lisszaboni kikötőből kifutott az első olyan flotta, amelyik Indiába akart eljutni azon az útvonalon, amelyet Bartolomeu Dias megnyitott a portugálok számára.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Dates, abbreviations ("1845. febr. 8. Edgeworthstown, † 1926. febr. 13. Oxford"), brackets
    #
    $test_string = <<'QUOTE';
Edgeworth, Francis Ysidro (1845. febr. 8. Edgeworthstown, † 1926. febr. 13. Oxford): ír közgazdász
és statisztikus, aki a közgazdaságtudományban maradandót alkotott a közömbösségi görbék rendszerének
megalkotásával. Nevéhez fűződik még a szerződési görbe és az úgynevezett Edgeworth-doboz vagy
Edgeworth-négyszög kidolgozása. ( Az utóbbit Pareto-féle box-diagrammnak is nevezik.) Mint
statisztikus, a korrelációszámítást fejlesztette tovább, s az index-számításban a bázis és a
tárgyidőszak fogyasztási szerkezettel számított indexek számtani átlagaként képzett indexet róla
nevezik Edgeworth-indexnek.
QUOTE

    $expected_sentences = [
'Edgeworth, Francis Ysidro (1845. febr. 8. Edgeworthstown, † 1926. febr. 13. Oxford): ír közgazdász és statisztikus, aki a közgazdaságtudományban maradandót alkotott a közömbösségi görbék rendszerének megalkotásával.',
'Nevéhez fűződik még a szerződési görbe és az úgynevezett Edgeworth-doboz vagy Edgeworth-négyszög kidolgozása.',
        '( Az utóbbit Pareto-féle box-diagrammnak is nevezik.)',
'Mint statisztikus, a korrelációszámítást fejlesztette tovább, s az index-számításban a bázis és a tárgyidőszak fogyasztási szerkezettel számított indexek számtani átlagaként képzett indexet róla nevezik Edgeworth-indexnek.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviation ("Dr."), date ("Komárom, 1825. február 18. – Budapest, Erzsébetváros, 1904. május 5.")
    #
    $test_string = <<'QUOTE';
Dr. Ásvay Jókai Móric (Komárom, 1825. február 18. – Budapest, Erzsébetváros, 1904. május 5.)
regényíró, a „nagy magyar mesemondó”, országgyűlési képviselő, főrendiházi tag, a Magyar
Tudományos Akadémia igazgató-tanácsának tagja, a Szent István-rend lovagja, a Kisfaludy
Társaság tagja, a Petőfi Társaság elnöke, a Dugonics Társaság tiszteletbeli tagja.
QUOTE

    $expected_sentences = [
'Dr. Ásvay Jókai Móric (Komárom, 1825. február 18. – Budapest, Erzsébetváros, 1904. május 5.) regényíró, a „nagy magyar mesemondó”, országgyűlési képviselő, főrendiházi tag, a Magyar Tudományos Akadémia igazgató-tanácsának tagja, a Szent István-rend lovagja, a Kisfaludy Társaság tagja, a Petőfi Társaság elnöke, a Dugonics Társaság tiszteletbeli tagja.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Dates
    #
    $test_string = <<'QUOTE';
Hszi Csin-ping (kínaiul: 习近平, pinjin, hangsúlyjelekkel: Xí Jìnpíng) (Fuping, Shaanxi
tartomány, 1953. június 1.) kínai politikus, 2008. március 15. óta a Kínai Népköztársaság
alelnöke, 2012. november 15. óta a KKP KB Politikai Bizottsága Állandó Bizottságának,
az ország de facto legfelső hatalmi grémiumának, valamint a KKP Központi Katonai
Bizottságának az elnöke. A várakozások szerint 2013 márciusától ő lesz a Kínai
Népköztársaság elnöke. 2010 óta számít az ország kijelölt következő vezetőjének.
QUOTE

    $expected_sentences = [
'Hszi Csin-ping (kínaiul: 习近平, pinjin, hangsúlyjelekkel: Xí Jìnpíng) (Fuping, Shaanxi tartomány, 1953. június 1.) kínai politikus, 2008. március 15. óta a Kínai Népköztársaság alelnöke, 2012. november 15. óta a KKP KB Politikai Bizottsága Állandó Bizottságának, az ország de facto legfelső hatalmi grémiumának, valamint a KKP Központi Katonai Bizottságának az elnöke.',
        'A várakozások szerint 2013 márciusától ő lesz a Kínai Népköztársaság elnöke.',
        '2010 óta számít az ország kijelölt következő vezetőjének.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Period in the middle of number
    #
    $test_string = <<'QUOTE';
A döntőben hibátlan gyakorlatára 16.066-os pontszámot kapott, akárcsak Louis Smith;
a holtversenyt a gyakorlatának magasabb kivitelezési pontszáma döntötte el Berki
javára, aki megnyerte első olimpiai aranyérmét.
QUOTE

    $expected_sentences = [
'A döntőben hibátlan gyakorlatára 16.066-os pontszámot kapott, akárcsak Louis Smith; a holtversenyt a gyakorlatának magasabb kivitelezési pontszáma döntötte el Berki javára, aki megnyerte első olimpiai aranyérmét.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Numbers
    #
    $test_string = <<'QUOTE';
2002-ben a KSI sportolójaként a junior Európa-bajnokságon lólengésben második,
csapatban 11. volt. A felnőtt mesterfokú magyar bajnokságon megnyerte a lólengést.
A debreceni szerenkénti világbajnokságon kilencedik lett. 2004-ben a vk-sorozatban
Párizsban 13., Cottbusban hatodik volt. A következő évben Rio de Janeiróban
vk-versenyt nyert. A ljubljanai Eb-n csapatban 10., lólengésben bronzérmes lett.
A világkupában Glasgowban ötödik, Gentben negyedik, Stuttgartban harmadik lett.
A birminghami világkupa-döntőn hatodik helyezést ért el.
QUOTE

    $expected_sentences = [
        '2002-ben a KSI sportolójaként a junior Európa-bajnokságon lólengésben második, csapatban 11. volt.',
        'A felnőtt mesterfokú magyar bajnokságon megnyerte a lólengést.',
        'A debreceni szerenkénti világbajnokságon kilencedik lett.',
        '2004-ben a vk-sorozatban Párizsban 13., Cottbusban hatodik volt.',
        'A következő évben Rio de Janeiróban vk-versenyt nyert.',
        'A ljubljanai Eb-n csapatban 10., lólengésben bronzérmes lett.',
        'A világkupában Glasgowban ötödik, Gentben negyedik, Stuttgartban harmadik lett.',
        'A birminghami világkupa-döntőn hatodik helyezést ért el.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Website name
    #
    $test_string = <<'QUOTE';
Már előtte a Blikk.hu-n is megnéztem a cikket. Tetszenek a képek, nagyon boldog vagyok.
QUOTE

    $expected_sentences =
      [ 'Már előtte a Blikk.hu-n is megnéztem a cikket.', 'Tetszenek a képek, nagyon boldog vagyok.' ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Name abbreviation
    #
    $test_string = <<'QUOTE';
Nagy hatással volt rá W.H. Auden, aki többek közt első operájának, a Paul Bunyannak a szövegkönyvét írta.
QUOTE

    $expected_sentences =
      [
'Nagy hatással volt rá W.H. Auden, aki többek közt első operájának, a Paul Bunyannak a szövegkönyvét írta.'
      ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Roman numeral
    #
    $test_string = <<'QUOTE';
1953-ban II. Erzsébet koronázására írta a Gloriana című operáját.
QUOTE

    $expected_sentences = [ '1953-ban II. Erzsébet koronázására írta a Gloriana című operáját.' ];

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
