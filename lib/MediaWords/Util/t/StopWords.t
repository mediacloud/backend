#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 17;

use_ok( 'MediaWords::Languages::en' );
use_ok( 'MediaWords::Languages::ru' );
use MediaWords::Languages::en;
use MediaWords::Languages::ru;

use Data::Dumper;

my $lang_en = MediaWords::Languages::en->new();
my $lang_ru = MediaWords::Languages::ru->new();

#<<<
ok($lang_en->get_tiny_stop_words(), 'lang_en_get_stop_words');

# Stop words
my $stop_words_en = $lang_en->get_tiny_stop_words();
my $stop_words_ru = $lang_ru->get_tiny_stop_words();
ok(scalar(keys(%{$stop_words_en})) >= 174, "stop words (en) count is correct");
ok(scalar(keys(%{$stop_words_ru})) >= 140, "stop words (ru) count is correct");

is ($stop_words_en->{'the'}, 1, "English test #1");
is ($stop_words_en->{'a'}, 1, "English test #2");
is ($stop_words_en->{'is'}, 1, "English test #3");
is ($stop_words_ru->{'и'}, 1, "Russian test #1");
is ($stop_words_ru->{'я'}, 1, "Russian test #2");

# Stop word stems
my $stop_word_stems_en = $lang_en->get_tiny_stop_word_stems();
my $stop_word_stems_ru = $lang_ru->get_tiny_stop_word_stems();

ok(scalar(keys(%{$stop_word_stems_en})) >= 154, "stop word stem (en) count is correct");
ok(scalar(keys(%{$stop_word_stems_ru})) >= 108, "stop word stem (ru) count is correct");

is ( $stop_word_stems_en->{'a'}, 1 , "Stemmed stop words" );

ok($lang_en->get_tiny_stop_word_stems(), "get_tiny_stop_word_stems()");
ok($lang_en->get_short_stop_word_stems(), 'get_short_stop_word_stems()');
ok($lang_en->get_long_stop_word_stems(), 'get_long_stop_word_stems()');
