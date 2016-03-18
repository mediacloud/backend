#!/usr/bin/perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 11 + 1;
use utf8;

use MediaWords::Languages::en;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::en->new();

    #
    # Period in number
    #
    $test_string = <<'QUOTE';
    Sentence contain version 2.0 of the text. Foo.
QUOTE

    $expected_sentences = [ 'Sentence contain version 2.0 of the text.', 'Foo.' ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # 'May' ending
    #
    $test_string = <<'QUOTE';
    Sentence ends in May. This is the next sentence. Foo.
QUOTE

    $expected_sentences = [ 'Sentence ends in May.', 'This is the next sentence.', 'Foo.' ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Punctuation
    #
    $test_string = <<'QUOTE';
    Leave the city! [Mega No!], l.
QUOTE

    $expected_sentences = [ 'Leave the city!', '[Mega No!], l.' ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Basic Unicode
    #
    $test_string = <<'QUOTE';
    Non Mega Não.
QUOTE

    $expected_sentences = [ 'Non Mega Não.' ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Unicode
    #
    $test_string = <<'QUOTE';
    Non Mega Não! [Mega No!], l.
QUOTE

    $expected_sentences = [ 'Non Mega Não!', '[Mega No!], l.', ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Quotation
    #
    $test_string =
"Perhaps that\x{2019}s the best thing the Nobel Committee did by awarding this year\x{2019}s literature prize to a non-dissident, someone whom Peter Englund of the Swedish Academy said was \x{201c}more a critic of the system, sitting within the system.\x{201d} They\x{2019}ve given him a chance to bust out.";

    $expected_sentences = [
'Perhaps that’s the best thing the Nobel Committee did by awarding this year’s literature prize to a non-dissident, someone whom Peter Englund of the Swedish Academy said was “more a critic of the system, sitting within the system.”',
        'They’ve given him a chance to bust out.',
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # String whitespace trimming
    #
    $test_string = <<'QUOTE';
        	  In another demonstration of cyberactivism and acvistim, Brazilian Internet users are gathering around a cause: to fight Senator Azeredo's Digital Crimes Bill.  	   This legal project, which intends to intervene severely in the way people use the Internet in Brazil is being heavily criticized by Brazil's academic field, left-wing parties and the Internet community.		
QUOTE

    $expected_sentences = [
'In another demonstration of cyberactivism and acvistim, Brazilian Internet users are gathering around a cause: to fight Senator Azeredo\'s Digital Crimes Bill.',
'This legal project, which intends to intervene severely in the way people use the Internet in Brazil is being heavily criticized by Brazil\'s academic field, left-wing parties and the Internet community.',
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Two spaces in the middle of the sentence
    #
    $test_string = <<'QUOTE';
    Although several opposition groups have called for boycotting the coming June 12  presidential election, it seems the weight of boycotting groups is much less than four years ago.
QUOTE

    $expected_sentences = [
'Although several opposition groups have called for boycotting the coming June 12 presidential election, it seems the weight of boycotting groups is much less than four years ago.',
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Non-breaking space
    #
    $test_string = <<"QUOTE";
    American Current TV journalists Laura Ling and Euna Lee have been  sentenced  to 12 years of hard labor (according to CNN).\x{a0} Jillian York  rounded up blog posts  for Global Voices prior to the journalists' sentencing.
QUOTE

    $expected_sentences = [
'American Current TV journalists Laura Ling and Euna Lee have been sentenced to 12 years of hard labor (according to CNN).',
        'Jillian York rounded up blog posts for Global Voices prior to the journalists\' sentencing.',
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # No space after a period
    #
    $test_string = <<'QUOTE';
    Anger is a waste of energy and what North Korea wants of you.We can and will work together and use our minds, to work this through.
QUOTE

    $expected_sentences = [
        'Anger is a waste of energy and what North Korea wants of you.',
        'We can and will work together and use our minds, to work this through.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Unicode's "…"
    #
    $test_string = <<'QUOTE';
    One of the most popular Brahmin community, with 28, 726 members, randomly claims: “we r clever & hardworking. no one can fool us…” The Brahmans community with 41952 members and the Brahmins of India community with 30588 members are also very popular.
QUOTE

    $expected_sentences = [
'One of the most popular Brahmin community, with 28, 726 members, randomly claims: “we r clever & hardworking. no one can fool us...”',
'The Brahmans community with 41952 members and the Brahmins of India community with 30588 members are also very popular.',
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
