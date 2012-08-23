#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}
use MediaWords::CommonLibs;

use Readonly;

use Test::NoWarnings;
use Test::More tests => 2 + 1;
use utf8;

use Data::Dumper;
use MediaWords::StoryVectors;

sub stem_test
{
    my ( $test_string, $expected_stems, $test_name ) = @_;
    my $stem_word_counts = MediaWords::StoryVectors::get_stem_word_counts_for_english_sentence( $test_string );

    #$Data::Dumper::Useqq = 1;
    #say Dumper ( $stem_word_counts );

    say join ' ', keys %{ $stem_word_counts };

    is_deeply( $stem_word_counts, $expected_stems, $test_name );

}

my $english_test_string = 'agreement agreements candy candies people';

my $english_expected_stems = {
    'agreement' => {
        'count' => 2,
        'word'  => 'agreement'
    },
    'peopl' => {
        'count' => 1,
        'word'  => 'people'
    },
    'candi' => {
        'count' => 2,
        'word'  => 'candy'
    }
};

my $foreign_expected_stems = {
    'газет' => {
        'count' => 1,
        'word'  => 'газета'
    },
    'агентств' => {
        'count' => 1,
        'word'  => 'агентства'
    },
    'владимир' => {
        'count' => 1,
        'word'  => 'владимир'
    },
    'não' => {
        'count' => 1,
        'word'  => 'não'
    },
    'американск' => {
        'count' => 1,
        'word'  => 'американских'
    },
    'александр' => {
        'count' => 1,
        'word'  => 'александр'
    },
    'автомобил' => {
        'count' => 1,
        'word'  => 'автомобиль'
    },
    'воен' => {
        'count' => 1,
        'word'  => 'военных'
    },
};

binmode STDOUT, ':encoding(UTF-8)';
stem_test( $english_test_string, $english_expected_stems, 'english test' );

my $foreign_test_string = <<'QUOTE';
 Não автомобиль агентства александр американских владимир военных газета 
QUOTE

stem_test( $foreign_test_string, $foreign_expected_stems, 'foreign test' );
