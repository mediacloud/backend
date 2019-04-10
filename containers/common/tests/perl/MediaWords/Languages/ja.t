#!/usr/bin/env prove

#
# Basic Japanese tokenizer test
# (more extensive testing is being on the Python side)
#

use strict;
use warnings;
use utf8;

use Test::More tests => 3;
use Test::Deep;
use Test::NoWarnings;

use MediaWords::Languages::ja;

use Data::Dumper;
use Readonly;

sub test_split_text_to_sentences($)
{
    my $lang = shift;

    my $input_text = <<'QUOTE';
ジアゼパムはてんかんや興奮の治療に用いられる。
This is some English text out of the blue. 
また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。
This is some more English text.
QUOTE

    my $expected_sentences = [
        'ジアゼパムはてんかんや興奮の治療に用いられる。',
        'This is some English text out of the blue.',
'また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。',
        'This is some more English text.',
    ];
    my $actual_sentences = $lang->split_text_to_sentences( $input_text );

    cmp_deeply( $actual_sentences, $expected_sentences );
}

sub test_tokenize($)
{
    my $lang = shift;

    my $input_sentence = 'pythonが大好きです';
    my $expected_words = [ 'python', '大好き', ];
    my $actual_words   = $lang->split_sentence_to_words( $input_sentence );

    cmp_deeply( $actual_words, $expected_words, 'tokenize()' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $lang = MediaWords::Languages::ja->new();

    test_split_text_to_sentences( $lang );
    test_tokenize( $lang );
}

main();
