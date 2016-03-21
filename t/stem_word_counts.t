#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use Test::NoWarnings;
use Test::More tests => 2 + 1;
use utf8;

use Data::Dumper;
use MediaWords::StoryVectors;

sub stem_test
{
    my ( $test_string, $expected_stems, $language, $test_name ) = @_;
    my $stem_word_counts = MediaWords::StoryVectors::_get_stem_word_counts_for_sentence( $test_string, $language );

    #$Data::Dumper::Useqq = 1;
    #say Dumper ( $stem_word_counts );

    say join ' ', keys %{ $stem_word_counts };

    is_deeply( $stem_word_counts, $expected_stems, $test_name );

}

my $english_test_string = 'agreement agreements candy candies people';

my $english_expected_stems = {
    'agreement' => {
        'count'    => 2,
        'word'     => 'agreement',
        'language' => 'en'
    },
    'peopl' => {
        'count'    => 1,
        'word'     => 'people',
        'language' => 'en'
    },
    'candi' => {
        'count'    => 2,
        'word'     => 'candy',
        'language' => 'en'
    }
};

my $foreign_expected_stems = {
    'газет' => {
        'count'    => 1,
        'word'     => 'газета',
        'language' => 'ru'
    },
    'агентств' => {
        'count'    => 1,
        'word'     => 'агентства',
        'language' => 'ru'
    },
    'владимир' => {
        'count'    => 1,
        'word'     => 'владимир',
        'language' => 'ru'
    },
    'não' => {
        'count'    => 1,
        'word'     => 'não',
        'language' => 'ru'
    },
    'американск' => {
        'count'    => 1,
        'word'     => 'американских',
        'language' => 'ru'
    },
    'александр' => {
        'count'    => 1,
        'word'     => 'александр',
        'language' => 'ru'
    },
    'автомобил' => {
        'count'    => 1,
        'word'     => 'автомобиль',
        'language' => 'ru'
    },
    'воен' => {
        'count'    => 1,
        'word'     => 'военных',
        'language' => 'ru'
    },
};

binmode STDOUT, ':encoding(UTF-8)';
stem_test( $english_test_string, $english_expected_stems, 'en', 'English test' );

my $foreign_test_string = <<'QUOTE';
 Não автомобиль агентства александр американских владимир военных газета 
QUOTE

stem_test( $foreign_test_string, $foreign_expected_stems, 'ru', 'Russian test' );
