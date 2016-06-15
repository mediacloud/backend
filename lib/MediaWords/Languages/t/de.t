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
use Test::More tests => 1 + 1;
use utf8;

use MediaWords::Languages::de;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::de->new();

    #
    # Simple paragraph + period in the middle of the date + period in the middle of the number
    #
    $test_string = <<'QUOTE';
Das Black Album (deutsch: Schwarzes Album) ist das sechzehnte Studioalbum des US-amerikanischen Musikers
Prince. Es erschien am 22. November 1994 bei dem Label Warner Bros. Records. Prince hatte das Album
bereits während der Jahre 1986 und 1987 aufgenommen und Warner Bros. Records wollte es ursprünglich
am 8. Dezember 1987 veröffentlichen. Allerdings zog Prince das Album eine Woche vor dem geplanten
Veröffentlichungstermin ohne Angabe von Gründen zurück. Anschließend entwickelte es sich mit über
250.000 Exemplaren zu einem der meistverkauften Bootlegs der Musikgeschichte, bis es sieben Jahre später
offiziell veröffentlicht wurde.
QUOTE

    $expected_sentences = [
        'Das Black Album (deutsch: Schwarzes Album) ist das sechzehnte Studioalbum des US-amerikanischen Musikers Prince.',
        'Es erschien am 22. November 1994 bei dem Label Warner Bros. Records.',
'Prince hatte das Album bereits während der Jahre 1986 und 1987 aufgenommen und Warner Bros. Records wollte es ursprünglich am 8. Dezember 1987 veröffentlichen.',
'Allerdings zog Prince das Album eine Woche vor dem geplanten Veröffentlichungstermin ohne Angabe von Gründen zurück.',
'Anschließend entwickelte es sich mit über 250.000 Exemplaren zu einem der meistverkauften Bootlegs der Musikgeschichte, bis es sieben Jahre später offiziell veröffentlicht wurde.'
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
