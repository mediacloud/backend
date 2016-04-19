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
use Test::More tests => 22;
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

sub test_tokenize()
{
    my ( $input_string, $expected_words );

    my $lang = MediaWords::Languages::en->new();

    # Normal apostrophe (')
    $input_string = "It's always sunny in Philadelphia.";
    $expected_words = [ "it's", "always", "sunny", "in", "philadelphia" ];
    is_deeply( $lang->tokenize( $input_string ), $expected_words, 'Tokenization with normal apostrophe' );

    # Right single quotation mark (’), normalized to apostrophe (')
    $input_string = "It’s always sunny in Philadelphia.";
    $expected_words = [ "it's", "always", "sunny", "in", "philadelphia" ];
    is_deeply( $lang->tokenize( $input_string ), $expected_words, 'Tokenization with fancy apostrophe' );

    # Hyphen without split
    $input_string = "near-total secrecy";
    $expected_words = [ "near-total", "secrecy" ];
    is_deeply( $lang->tokenize( $input_string ), $expected_words, 'Tokenization with hyphen (no split)' );

    # Hyphen with split (where it's being used as a dash)
    $input_string = "A Pythagorean triple - named for the ancient Greek Pythagoras";
    $expected_words = [ 'a', 'pythagorean', 'triple', 'named', 'for', 'the', 'ancient', 'greek', 'pythagoras' ];
    is_deeply( $lang->tokenize( $input_string ), $expected_words, 'Tokenization with hyphen (split)' );

    # Quotes
    $input_string   = 'it was in the Guinness Book of World Records as the "most difficult mathematical problem"';
    $expected_words = [
        'it',      'was', 'in',  'the',  'guinness',  'book',         'of', 'world',
        'records', 'as',  'the', 'most', 'difficult', 'mathematical', 'problem'
    ];
    is_deeply( $lang->tokenize( $input_string ), $expected_words, 'Quote removal while tokenizing' );
}

sub test_stem()
{
    my $lang = MediaWords::Languages::en->new();

    # from http://en.wikipedia.org/wiki/Stemming
    my $stemmer_test_en_text = <<'__END_TEST_CASE__';
    In linguistic morphology, stemming is the process for reducing inflected (or sometimes derived) words to their stem,
    base or root form – generally a written word form. The stem need not be identical to the morphological root of the
    word; it is usually sufficient that related words map to the same stem, even if this stem is not in itself a valid
    root. The algorithm has been a long-standing problem in computer science; the first paper on the subject was published
    in 1968. The process of stemming, often called conflation, is useful in search engines for query expansion or indexing
    and other natural language processing problems.
__END_TEST_CASE__

    my @split_words = @{ $lang->tokenize( $stemmer_test_en_text ) };

    my $lingua_stem = Lingua::Stem::Snowball->new( lang => 'en', encoding => 'UTF-8' );

    my $lingua_stem_result = [ $lingua_stem->stem( \@split_words ) ];
    my $stem_result        = $lang->stem( @split_words );

    is_deeply( $stem_result, $lingua_stem_result, "Stemmer compare test" );

    isnt( $lingua_stem_result, $stemmer_test_en_text, "Stemmed text is changed" );
    ok( length( $lingua_stem_result ) > 0, "Stemmed text is nonempty" );

    # Apostrophes
    is_deeply( $lang->stem( qw/Katz's Delicatessen/ ), [ qw/ katz delicatessen / ], 'Stemming with normal apostrophe' );
    is_deeply( $lang->stem( qw/it’s toasted/ ), [ qw/ it toast / ], 'Stemming with right single quotation mark' );
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_get_sentences();
    test_tokenize();
    test_stem();
}

main();
