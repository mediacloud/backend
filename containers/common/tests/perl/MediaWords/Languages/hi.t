#!/usr/bin/env prove

use strict;
use warnings;
use utf8;

use Test::More tests => 24;
use Test::Differences;
use Test::NoWarnings;

use MediaWords::Languages::hi;

use Data::Dumper;
use Readonly;

sub test_stem($)
{
    my $lang = shift;

# https://github.com/apache/lucene-solr/blob/master/lucene/analysis/common/src/test/org/apache/lucene/analysis/hi/TestHindiStemmer.java
    my $tokens_and_stems = {

        # Masculine noun inflections
        'लडका'          => 'लडका',
        'लडके'          => 'लडके',
        'लडकों'       => 'लडकों',
        'गुरु'          => 'गुरु',
        'गुरुओं'    => 'गुरु',
        'दोस्त'       => 'दोस्त',
        'दोस्तों' => 'दोस',

        # Feminine noun inflections
        'लडकी'                      => 'लडकी',
        'लडकियों'             => 'लडकियों',
        'किताब'                   => 'किताब',
        'किताबें'             => 'किताबे',
        'किताबों'             => 'किताबो',
        'आध्यापीका'       => 'आध्यापीका',
        'आध्यापीकाएं' => 'आध्यापीकाएं',
        'आध्यापीकाओं' => 'आध्यापीकाओं',

        # Some verb forms
        'खाना' => 'खाना',
        'खाता' => 'खाता',
        'खाती' => 'खाती',
        'खा'       => 'खा',

        # Exceptions
        'कठिनाइयां' => 'कठिना',
        'कठिन'                => 'कठिन',

        # Empty tokens
        '' => '',
    };

    for my $token ( keys %{ $tokens_and_stems } )
    {
        my $expected_stem = $tokens_and_stems->{ $token };
        my $actual_stem = $lang->stem_words( [ $token ] )->[ 0 ];
        is( $actual_stem, $expected_stem, "stem_words(): $token" );
    }
}

sub test_split_text_to_sentences($)
{
    my $lang = shift;

    #
    # Simple paragraph
    #
    my $input_text = <<'QUOTE';
अंटार्कटिका (या अन्टार्टिका) पृथ्वी का दक्षिणतम महाद्वीप है, जिसमें दक्षिणी
ध्रुव अंतर्निहित है। यह दक्षिणी गोलार्द्ध के अंटार्कटिक क्षेत्र और लगभग पूरी तरह
से अंटार्कटिक वृत के दक्षिण में स्थित है। यह चारों ओर से दक्षिणी महासागर से घिरा
हुआ है। अपने 140 लाख वर्ग किलोमीटर (54 लाख वर्ग मील) क्षेत्रफल के साथ यह, एशिया,
अफ्रीका, उत्तरी अमेरिका और दक्षिणी अमेरिका के बाद, पृथ्वी का पांचवां सबसे बड़ा
महाद्वीप है, अंटार्कटिका का 98% भाग औसतन 1.6 किलोमीटर मोटी बर्फ से आच्छादित है।
QUOTE

    my $expected_sentences = [
'अंटार्कटिका (या अन्टार्टिका) पृथ्वी का दक्षिणतम महाद्वीप है, जिसमें दक्षिणी ध्रुव अंतर्निहित है।',
'यह दक्षिणी गोलार्द्ध के अंटार्कटिक क्षेत्र और लगभग पूरी तरह से अंटार्कटिक वृत के दक्षिण में स्थित है।',
'यह चारों ओर से दक्षिणी महासागर से घिरा हुआ है।',
'अपने 140 लाख वर्ग किलोमीटर (54 लाख वर्ग मील) क्षेत्रफल के साथ यह, एशिया, अफ्रीका, उत्तरी अमेरिका और दक्षिणी अमेरिका के बाद, पृथ्वी का पांचवां सबसे बड़ा महाद्वीप है, अंटार्कटिका का 98% भाग औसतन 1.6 किलोमीटर मोटी बर्फ से आच्छादित है।',
    ];
    my $actual_sentences = $lang->split_text_to_sentences( $input_text );

    eq_or_diff( $actual_sentences, $expected_sentences );
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $lang = MediaWords::Languages::hi->new();

    test_stem( $lang );
    test_split_text_to_sentences( $lang );
}

main();
