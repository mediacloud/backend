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

use MediaWords::Languages::da;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::da->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Sør-Georgia (engelsk: South Georgia) er ei øy i Søratlanteren som høyrer til det britiske oversjøiske territoriet
Sør-Georgia og Sør-Sandwichøyane. Argentina gjer krav på Sør-Georgia og resten av dei britiske territoria i
Søratlanteren. Sør-Georgia har eit areal på 3 756 km² og er 170 km lang og 30 km brei. Det høgste punktet på
øya er Mount Paget på 2 934 moh. I alt elleve fjelltoppar er høgare enn 2 000 moh. 75 % av øya er dekt av snø
og is. Det er meir enn 150 isbrear på øya, og Nordenskiöldbreen er den største. Øya har ingen fastbuande, men har
forskingspersonell som er tilknytte museumsdrifta og forskingsstasjonane på Birdøya og King Edward Point.
QUOTE

    $expected_sentences = [
'Sør-Georgia (engelsk: South Georgia) er ei øy i Søratlanteren som høyrer til det britiske oversjøiske territoriet Sør-Georgia og Sør-Sandwichøyane.',
        'Argentina gjer krav på Sør-Georgia og resten av dei britiske territoria i Søratlanteren.',
        'Sør-Georgia har eit areal på 3 756 km² og er 170 km lang og 30 km brei.',
        'Det høgste punktet på øya er Mount Paget på 2 934 moh.',
        'I alt elleve fjelltoppar er høgare enn 2 000 moh.',
        '75 % av øya er dekt av snø og is.',
        'Det er meir enn 150 isbrear på øya, og Nordenskiöldbreen er den største.',
'Øya har ingen fastbuande, men har forskingspersonell som er tilknytte museumsdrifta og forskingsstasjonane på Birdøya og King Edward Point.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Date ("14. januar 1776")
    #
    $test_string = <<'QUOTE';
Sør-Georgia vart oppdaga av Antoine de la Roché i april 1675, fartøyet hans var kome ut av kurs på ein segltur
frå Lima i Peru til England. Øya vart på ny sett av spanjolen Gregorio Jerez i 1756. James Cook kom til
Sør-Georgia 14. januar 1776 og var den fyrste som gjekk i land på øya.
QUOTE

    $expected_sentences = [
'Sør-Georgia vart oppdaga av Antoine de la Roché i april 1675, fartøyet hans var kome ut av kurs på ein segltur frå Lima i Peru til England.',
        'Øya vart på ny sett av spanjolen Gregorio Jerez i 1756.',
        'James Cook kom til Sør-Georgia 14. januar 1776 og var den fyrste som gjekk i land på øya.'
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
