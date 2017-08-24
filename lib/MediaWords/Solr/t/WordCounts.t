#!/usr/bin/env perl

use strict;
use warnings;

# test MediaWords::Solr::WordCounts

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use MediaWords::CommonLibs;

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
    my $wc = MediaWords::Solr::WordCounts->new( include_stopwords => 1 );

    my $sentences = [ 'foo and bar and baz', 'foo and bat and foo and baz', ];

    my $got_stems      = $wc->count_stems( $sentences );
    my $expected_stems = {
        foo => { count => 3, terms => { foo => 3 } },
        and => { count => 5, terms => { and => 5 } },
        bar => { count => 1, terms => { bar => 1 } },
        baz => { count => 2, terms => { baz => 2 } },
        bat => { count => 1, terms => { bat => 1 } }
    };

    cmp_deeply( $got_stems, $expected_stems, "counts ngram_size = 1" );

    $wc->ngram_size( 2 );

    my $got_bigrams      = $wc->count_stems( $sentences );
    my $expected_bigrams = {
        'foo and' => { count => 3, terms => { 'foo and' => 3 } },
        'and bar' => { count => 1, terms => { 'and bar' => 1 } },
        'bar and' => { count => 1, terms => { 'bar and' => 1 } },
        'and baz' => { count => 2, terms => { 'and baz' => 2 } },
        'and bat' => { count => 1, terms => { 'and bat' => 1 } },
        'bat and' => { count => 1, terms => { 'bat and' => 1 } },
        'and foo' => { count => 1, terms => { 'and foo' => 1 } },
    };

    cmp_deeply( $got_bigrams, $expected_bigrams, "counts ngram_size = 2" );
}

sub main
{
    test_count_stems();

    done_testing();
}

main();
