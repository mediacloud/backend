#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

# test MediaWords::Solr::WordCounts

use MediaWords::CommonLibs;

use MediaWords::Test::Supervisor;
use MediaWords::Test::Solr;

use English '-no_match_vars';

use Test::More;
use Test::Deep;

BEGIN
{
    use_ok( 'MediaWords::Solr::WordCounts' );
}

# test count_stems() function that does the core word counting logic
sub test_count_stems
{
    my $wc = MediaWords::Solr::WordCounts->new( include_stopwords => 0 );

    my $sentences_and_story_languages = [
        {
            'sentence' =>
              'La Revolución mexicana fue un conflicto armado que se inició en México el 20 de noviembre de 1910.',
            'story_language' => 'es',
            'language'       => 'es',
        },
        {
            'sentence'       => 'Kris Jenner, Caitlyn Jenner, Kourtney Kardashian, Kim Kardashian, Kim Kardashian again',
            'story_language' => 'en',
            'language'       => 'en',
        },
        {
            'sentence'       => 'Khloé Kardashian, Rob Kardashian, Kendall Jenner, Kylie Jenner',
            'story_language' => 'en',
            'language'       => 'en',
        }
    ];

    my $got_stems = $wc->count_stems( $sentences_and_story_languages );

    my $expected_stems = {
        'jenner' => {
            'count' => 4,
            'terms' => { 'jenner' => 4 }
        },
        'revolu' => {
            'terms' => { "revolución" => 1 },
            'count' => 1
        },
        'mexican' => {
            'count' => 1,
            'terms' => { 'mexicana' => 1 }
        },
        'conflict' => {
            'count' => 1,
            'terms' => { 'conflicto' => 1 }
        },
        'noviembr' => {
            'count' => 1,
            'terms' => { 'noviembre' => 1 }
        },
        'kardashian' => {
            'terms' => { 'kardashian' => 5 },
            'count' => 5
        },
        'kourtney' => {
            'count' => 1,
            'terms' => { 'kourtney' => 1 }
        },
        'kim' => {
            'count' => 2,
            'terms' => { 'kim' => 2 }
        },
        'armad' => {
            'terms' => { 'armado' => 1 },
            'count' => 1
        },
        'kyli' => {
            'terms' => { 'kylie' => 1 },
            'count' => 1
        },
        'rob' => {
            'count' => 1,
            'terms' => { 'rob' => 1 }
        },
        "khloé" => {
            'terms' => { "khloé" => 1 },
            'count' => 1
        },
        'kendal' => {
            'count' => 1,
            'terms' => { 'kendall' => 1 }
        },
        'mexic' => {
            'terms' => { "méxico" => 1 },
            'count' => 1
        },
        'kris' => {
            'count' => 1,
            'terms' => { 'kris' => 1 }
        },
        'caitlyn' => {
            'terms' => { 'caitlyn' => 1 },
            'count' => 1
        },
        'inic' => {
            'terms' => { "inició" => 1 },
            'count' => 1
        }
    };

    cmp_deeply( $got_stems, $expected_stems, "counts ngram_size = 1" );

    $wc->ngram_size( 2 );

    my $got_bigrams = $wc->count_stems( $sentences_and_story_languages );

    my $expected_bigrams = {
        'rob kardashian' => {
            'count' => 1,
            'terms' => { 'rob kardashian' => 1 }
        },
        'kourtney kardashian' => {
            'count' => 1,
            'terms' => { 'kourtney kardashian' => 1 }
        },
        'conflicto armado' => {
            'count' => 1,
            'terms' => { 'conflicto armado' => 1 }
        },
        "revolución mexicana" => {
            'count' => 1,
            'terms' => { "revolución mexicana" => 1 }
        },
        "armado inició" => {
            'terms' => { "armado inició" => 1 },
            'count' => 1
        },
        "méxico noviembre" => {
            'terms' => { "méxico noviembre" => 1 },
            'count' => 1
        },
        'kris jenner' => {
            'terms' => { 'kris jenner' => 1 },
            'count' => 1
        },
        'jenner kylie' => {
            'count' => 1,
            'terms' => { 'jenner kylie' => 1 }
        },
        'mexicana conflicto' => {
            'terms' => { 'mexicana conflicto' => 1 },
            'count' => 1
        },
        'caitlyn jenner' => {
            'count' => 1,
            'terms' => { 'caitlyn jenner' => 1 }
        },
        'kendall jenner' => {
            'count' => 1,
            'terms' => { 'kendall jenner' => 1 }
        },
        'kylie jenner' => {
            'count' => 1,
            'terms' => { 'kylie jenner' => 1 }
        },
        'kardashian rob' => {
            'count' => 1,
            'terms' => { 'kardashian rob' => 1 }
        },
        "khloé kardashian" => {
            'terms' => { "khloé kardashian" => 1 },
            'count' => 1
        },
        'kardashian kim' => {
            'count' => 2,
            'terms' => { 'kardashian kim' => 2 }
        },
        'kim kardashian' => {
            'count' => 2,
            'terms' => { 'kim kardashian' => 2 }
        },
        'jenner caitlyn' => {
            'terms' => { 'jenner caitlyn' => 1 },
            'count' => 1
        },
        'kardashian kendall' => {
            'terms' => { 'kardashian kendall' => 1 },
            'count' => 1
        },
        "inició méxico" => {
            'count' => 1,
            'terms' => { "inició méxico" => 1 }
        },
        'jenner kourtney' => {
            'terms' => { 'jenner kourtney' => 1 },
            'count' => 1
        }
    };

    cmp_deeply( $got_bigrams, $expected_bigrams, "counts ngram_size = 2" );
}

sub test_get_words
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::Solr::create_indexed_test_story_stack(
        $db,
        {
            medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 15 ) ] },
            medium_2 => { feed_2 => [ map { "story_$_" } ( 16 .. 25 ) ] },
            medium_3 => { feed_3 => [ map { "story_$_" } ( 26 .. 50 ) ] },
        }
    );

    my $story_sentence = $db->query( <<SQL )->hash;
select * from story_sentences order by story_sentences_id limit 1
SQL
    my ( $first_word ) = split( ' ', $story_sentence->{ sentence } );

    my $re = '(?isx)[[:<:]]' . $first_word;

    my $matching_sentences = $db->query( <<SQL, $re )->hashes;
select
        ss.*,
        s.language story_language
    from
        story_sentences ss
        join stories s using ( stories_id )
    where
        sentence ~ ?
SQL

    my $wc = MediaWords::Solr::WordCounts->new( include_stopwords => 1 );

    my $num_words = 10;

    my $expected_stems  = $wc->count_stems( $matching_sentences );
    my $expected_counts = [];
    while ( my ( $stem, $data ) = each( %{ $expected_stems } ) )
    {
        push( @{ $expected_counts }, { stem => $stem, count => $data->{ count } } );
    }
    $expected_counts = [ sort { $b->{ count } <=> $a->{ count } } @{ $expected_counts } ];
    splice( @{ $expected_counts }, 10 );

    my $test_wc = MediaWords::Solr::WordCounts->new(
        db                => $db,
        q                 => "$first_word*",
        num_words         => $num_words,
        include_stopwords => 1
    );
    my $got_counts = $test_wc->get_words();

    # term is hard to test without reproducing lots of logic, and term counting is already tested above
    map { delete( $_->{ term } ) } @{ $got_counts };

    $got_counts      = [ sort { $a->{ stem } cmp $b->{ stem } } @{ $got_counts } ];
    $expected_counts = [ sort { $a->{ stem } cmp $b->{ stem } } @{ $expected_counts } ];

    is_deeply( $got_counts, $expected_counts, "get_words" );
}

sub main
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_count_stems();

    MediaWords::Test::Supervisor::test_with_supervisor( \&test_get_words, [ qw/solr_standalone/ ] );

    done_testing();
}

main();
