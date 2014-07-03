package MediaWords::Solr::WordCounts;

# handle direct word counting from solr server results.

# this is written separately from MediaWords::Solr::count_words so that this
# code can run on the solr server itself and be requested over http by
# MediaWords::Solr::count_words.

use strict;
use warnings;

use Data::Dumper;
use Encode;
use Getopt::Long;
use HTTP::Request::Common;
use HTTP::Server::Simple::CGI;
use IO::Socket::INET;
use JSON;
use LWP::UserAgent;
use Lingua::Stem::Snowball;
use List::Util;
use URI::Escape;

use MediaWords::Solr;
use MediaWords::Util::Config;

# max number of random sentences to fetch
use constant MAX_RANDOM_SENTENCES => 1000;

# number of words to return
use constant NUM_RETURN_WORDS => 500;

# max number of lines that can be in the solr http response header
use constant MAX_HEADER_LINES => 100;

# set any duplicate lines blank.
sub blank_dup_lines
{
    my ( $lines, $dup_lines ) = @_;

    map { $dup_lines->{ $_ } ? ( $_ = '' ) : ( $dup_lines->{ $_ } = 1 ); } @{ $lines };
}

# parse the text and return a count of stems and terms in the sentence in the
# following format:
# { $stem => { count => $stem_count, terms => { $term => $term_count } } }
#
# this function is where virtually all of the time in the script is spent, and
# had been carefully tuned, so do not change anything without testing performance
# impacts
sub count_stems
{
    my ( $lines, $dup_lines, $languages ) = @_;

    blank_dup_lines( $lines, $dup_lines );

    # tokenize each line and add count to $words for each token
    my $words = {};
    for my $line ( @{ $lines } )
    {
        # very long lines tend to be noise -- html text and the like.
        # lc here instead of individual word for better performance
        $line = lc( substr( $line, 0, 256 ) );

        # for some reason, encode( 'utf8', $line ) does not make \w match unicode letters,
        # but the following does
        Encode::_utf8_on( $line );

        while ( $line =~ /(\w+)/g )
        {
            my $word           = $1;
            my $word_no_digits = $word;
            $word_no_digits =~ s/\d//g;
            $words->{ $word }++ if ( length( $word_no_digits ) > 2 );
        }
    }

    # now we need to stem the words.  It's faster to stem as a single set of words.  we
    # don't want to use caching with the stemming because we are finding the unique
    # words ourselves.
    my @unique_words = keys( %{ $words } );
    my $stems        = [ @unique_words ];

    for my $lang ( @{ $languages } )
    {
        my $language = MediaWords::Languages::Language::language_for_code( $lang );
        next unless ( $language );

        $stems = $language->stem( @{ $stems } );
    }

    my $stem_counts = {};
    for ( my $i = 0 ; $i < @{ $stems } ; $i++ )
    {
        $stem_counts->{ $stems->[ $i ] }->[ 0 ] += $words->{ $unique_words[ $i ] };
        $stem_counts->{ $stems->[ $i ] }->[ 1 ]->{ $unique_words[ $i ] } += $words->{ $unique_words[ $i ] };
    }

    return $stem_counts;
}

# Check whether the string is valid UTF-8
sub is_valid_utf8($)
{
    my $s = shift;

    my $valid = 1;

    Encode::_utf8_on( $s );

    $valid = 0 unless ( utf8::valid( $s ) );

    Encode::_utf8_off( $s );

    return $valid;
}

# get the count_stem results from one run of count_stems against a block of lines
sub merge_block_words
{
    my ( $block_words, $words ) = @_;

    for my $stem ( keys( %{ $block_words } ) )
    {
        next unless ( $stem );

        $words->{ $stem }->{ count } += $block_words->{ $stem }->[ 0 ]++;

        my $term_stem_counts = $words->{ $stem }->{ terms } ||= {};
        for my $term ( keys( %{ $block_words->{ $stem }->[ 1 ] } ) )
        {
            $term_stem_counts->{ $term } += $block_words->{ $stem }->[ 1 ]->{ $term };
        }
    }
}

# stopword counts by list of languages
sub get_stopworded_counts
{
    my ( $words, $languages ) = @_;

    for my $lang ( @{ $languages } )
    {
        my $language = MediaWords::Languages::Language::language_for_code( $lang );

        next unless ( $language );

        my $stopstems = $language->get_long_stop_word_stems();

        my $stopworded_words = [];
        for my $word ( @{ $words } )
        {
            next if ( length( $word->{ stem } ) < 3 );

            # we have restem the word because solr uses a different stemming implementation
            my $stem = $language->stem( $word->{ term } )->[ 0 ];

            push( @{ $stopworded_words }, $word ) unless ( $stopstems->{ $stem } );
        }

        $words = $stopworded_words;
    }

    return $words;
}

# connect to solr server directly and count the words resulting from the query
sub words_from_solr_server
{
    my ( $q, $fqs, $languages, $file ) = @_;

    $languages = [ 'en' ] unless ( $languages && @{ $languages } );

    print STDERR "generating word hash ...\n";
    print STDERR Dumper( $q, $fqs, $languages );

    return [] unless ( $q || @{ $fqs } );

    my $start_generation_time = time();

    my $data = MediaWords::Solr::query(
        { q => $q, fq => $fqs, rows => MAX_RANDOM_SENTENCES, fl => 'sentence', sort => 'random_1 asc' } );

    my @sentences = map { $_->{ sentence } } @{ $data->{ response }->{ docs } };

    my $dup_lines = {};
    my $words     = {};

    print STDERR "counting sentences...\n";
    my $block_words = count_stems( \@sentences, $dup_lines, $languages );
    merge_block_words( $block_words, $words );

    my $merge_end_time = time;

    print STDERR "generating word list ...\n";
    my @word_list;
    while ( my ( $stem, $count ) = each( %{ $words } ) )
    {
        push( @word_list, [ $stem, $count->{ count } ] );
    }

    print STDERR "sorting ...\n";
    @word_list = sort { $b->[ 1 ] <=> $a->[ 1 ] } @word_list;

    print STDERR "cutting list ...\n";
    my $num_pre_sw_words = NUM_RETURN_WORDS * ( 1 + scalar( @{ $languages } ) );
    splice( @word_list, $num_pre_sw_words );

    my $counts = [];
    for my $w ( @word_list )
    {
        my $terms = $words->{ $w->[ 0 ] }->{ terms };
        my ( $max_term, $max_term_count );
        while ( my ( $term, $term_count ) = each( %{ $terms } ) )
        {
            if ( !$max_term || ( $term_count > $max_term_count ) )
            {
                $max_term       = $term;
                $max_term_count = $term_count;
            }
        }

        if ( !is_valid_utf8( $w->[ 0 ] ) || !is_valid_utf8( $max_term ) )
        {
            print STDERR "invalid utf8: $w->[ 0 ] / $max_term\n";
            next;
        }

        push( @{ $counts }, { stem => $w->[ 0 ], count => $w->[ 1 ], term => $max_term } );
    }

    $counts = get_stopworded_counts( $counts, $languages );

    splice( @{ $counts }, NUM_RETURN_WORDS );

    return $counts;
}

1;
