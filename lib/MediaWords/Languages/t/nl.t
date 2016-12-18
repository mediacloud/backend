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

use MediaWords::Languages::nl;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::nl->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Onder neogotiek wordt een 19e-eeuwse stroming in de architectuur verstaan die zich geheel heeft
laten inspireren door de middeleeuwse gotiek. De neogotiek ontstond in Engeland en was een
reactie op de strakke, koele vormen van het classicisme met haar uitgesproken rationele karakter.
De neogotiek vond haar oorsprong in de romantiek met haar belangstelling voor de middeleeuwen.
QUOTE

    $expected_sentences = [
'Onder neogotiek wordt een 19e-eeuwse stroming in de architectuur verstaan die zich geheel heeft laten inspireren door de middeleeuwse gotiek.',
'De neogotiek ontstond in Engeland en was een reactie op de strakke, koele vormen van het classicisme met haar uitgesproken rationele karakter.',
        'De neogotiek vond haar oorsprong in de romantiek met haar belangstelling voor de middeleeuwen.'
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
De vulkaan, meestal gewoon Tongariro genoemd, heeft een hoogte van 1978 meter. Ruim 260.000
jaar geleden barstte de vulkaan voor het eerst uit. De Tongariro bestaat uit ten minste twaalf
toppen. De Ngarahoe, vaak gezien als een aparte berg, is eigenlijk een bergtop met krater
van de Tongariro. Het is de meest actieve vulkaan in het gebied. Sinds 1839 hebben er meer
dan zeventig uitbarstingen plaatsgevonden. De meest recente uitbarsting was op 21 november
2012 om 13:22 uur, waarbij een aswolk tot 4213 m is gerapporteerd. Dit was slechts 3,5 maand
na de voorlaatste uitbarsting op 6 augustus 2012.
QUOTE

    $expected_sentences = [
        'De vulkaan, meestal gewoon Tongariro genoemd, heeft een hoogte van 1978 meter.',
        'Ruim 260.000 jaar geleden barstte de vulkaan voor het eerst uit.',
        'De Tongariro bestaat uit ten minste twaalf toppen.',
        'De Ngarahoe, vaak gezien als een aparte berg, is eigenlijk een bergtop met krater van de Tongariro.',
        'Het is de meest actieve vulkaan in het gebied.',
        'Sinds 1839 hebben er meer dan zeventig uitbarstingen plaatsgevonden.',
        'De meest recente uitbarsting was op 21 november 2012 om 13:22 uur, waarbij een aswolk tot 4213 m is gerapporteerd.',
        'Dit was slechts 3,5 maand na de voorlaatste uitbarsting op 6 augustus 2012.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviation ("m.a.w")
    #
    $test_string = <<'QUOTE';
Aeroob betekent dat een organisme alleen met zuurstof kan gedijen, m.a.w dat het zuurstof
gebruikt. Dit in tegenstelling tot anaerobe organismen, die geen zuurstof nodig hebben.
QUOTE

    $expected_sentences = [
        'Aeroob betekent dat een organisme alleen met zuurstof kan gedijen, m.a.w dat het zuurstof gebruikt.',
        'Dit in tegenstelling tot anaerobe organismen, die geen zuurstof nodig hebben.'
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
