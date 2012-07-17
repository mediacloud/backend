#!/usr/bin/env perl

# FIXME:description
# FIXME http://en.wikipedia.org/wiki/Tf*idf
#
# Valid types:
#   tf -- Term frequency (TF) (default)
#   idf -- Inverse Document Frequency (IDF)
#   nidf -- Normalised Inverse Document Frequency (normalised IDF)
#   tbrs -- Term-based Random Sampling
#
# usage: mediawords_generate_stopwords.pl \
#   [--type=tf|idf|nidf|tbrs] \
#   [--term_limit=i] \
#   [--sentence_limit=i] \
#   [--stoplist_threshold=i]
#
# example:
# FIXME:example

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Getopt::Long;
use MediaWords::StoryVectors;
use Encode;

# Term frequency (TF)
sub gen_term_frequency
{
    my ( $db, $term_limit, $sentence_limit, $stoplist_threshold ) = @_;

    # Using 'story_sentence_words' might be a more natural choice, but that list of words
    # might already be stemmed by this way or another, so let's re-tokenize sentences from
    # 'story_sentences' to separate words again.

    # 'story_sentences'
    #   story_sentences_id
    #   stories_id
    #   sentence_number
    #   sentence
    #   media_id
    #   publish_date

    # Temp. table for storing word counts
    $db->query( "DROP TABLE IF EXISTS temp_term_counts" );
    $db->query(
        "CREATE TEMPORARY TABLE temp_term_counts (
                    term        VARCHAR(256) NOT NULL
                 ) WITH (OIDS=FALSE)"
    );

    # Sentence count (to give a sense of progress)
    if ( $sentence_limit == 0 )
    {
        my $sentence_limit = $db->query(
            "SELECT reltuples
                                          FROM pg_class
                                          WHERE relname = 'story_sentences'"
        )->hash()->{ reltuples };
        die "Sentence count is 0.\n" unless $sentence_limit;
    }
    printf STDERR "Will go through ~%d sentences.\n", $sentence_limit;

    my $sentences_rs =
      $db->query( "SELECT sentence FROM story_sentences ORDER BY story_sentences_id LIMIT $sentence_limit" );
    my $sentence_count = 0;
    my $terms_analysed = 0;
    while ( my $sentence = $sentences_rs->hash() )
    {
        if ( ++$sentence_count % 1000 == 0 )
        {
            printf STDERR "Tokenizing sentence %d out of ~%d...\n", $sentence_count, $sentence_limit;
        }

        my $terms = MediaWords::StoryVectors::tokenize( [ $sentence->{ sentence } ] );

        $db->dbh->do( "COPY temp_term_counts (term) FROM STDIN" );
        for ( my $i = 0 ; $i < $#$terms ; $i++ )
        {
            my $term = $terms->[ $i ];

            # Definitely not a stopword and probably not a word anyway.
            next if ( length( $term ) > 256 );

            $db->dbh->pg_putcopydata( encode_utf8( $term ) . "\n" );

            # Term limit reached
            ++$terms_analysed;
            if ( $term_limit != 0 )
            {
                last if ( $terms_analysed >= $term_limit );
            }
        }

        $db->dbh->pg_putcopyend();
    }

    # Print term count
    my $term_count_rs = $db->query(
        "SELECT
                                    term,
                                    COUNT(term) AS term_count
                                  FROM temp_term_counts
                                  GROUP BY term
                                  ORDER BY term_count DESC
                                  LIMIT $stoplist_threshold"
    );
    binmode( STDERR, ":utf8" );
    while ( my $term_count = $term_count_rs->hash() )
    {
        printf STDERR "%s\t%d\n", $term_count->{ term }, $term_count->{ term_count };
    }

    # Cleanup
    $db->query( "DROP TABLE temp_term_counts" );

}

# Prepare the temporary table for IDF / NIDF calculations
sub _fill_temp_table_for_idf
{
    my ( $db, $term_limit, $sentence_limit ) = @_;

        # Temp. table for storing word counts
    $db->query( "DROP TABLE IF EXISTS temp_term_counts" );
    $db->query(
        "CREATE TEMPORARY TABLE temp_term_counts (
                    term        VARCHAR(256) NOT NULL
                 ) WITH (OIDS=FALSE)"
    );

    # Sentence count (to give a sense of progress)
    if ( $sentence_limit == 0 )
    {
        die "You would be better of setting a sentence limit when using IDF.\n";
    }
    printf STDERR "Will go through ~%d sentences.\n", $sentence_limit;

    my $stories_rs = $db->query(
        " SELECT
                        stories_id,
                        ARRAY_TO_STRING(ARRAY_AGG(sentence), ' ') AS story
                    FROM (
                        SELECT
                            stories_id,
                            sentence
                        FROM story_sentences
                        ORDER BY stories_id, sentence_number
                        LIMIT $sentence_limit
                    ) AS story_sentences_limited
                    GROUP BY stories_id
                    ORDER BY stories_id"
    );
    my $story_count    = 0;
    my $terms_analysed = 0;
    while ( my $story = $stories_rs->hash() )    # for every document
    {
        my $i    = 0;
        my $term = '';

        if ( ++$story_count % 10 == 0 )
        {
            printf STDERR "Tokenizing story %d...\n", $story_count;
        }

        my $terms = MediaWords::StoryVectors::tokenize( [ $story->{ story } ] );
        my %unique_terms;                        # of a document

        for ( $i = 0 ; $i < $#$terms ; $i++ )
        {
            $term = $terms->[ $i ];

            # Definitely not a stopword and probably not a word anyway.
            next if ( length( $term ) > 256 );

            $unique_terms{ $term } = 1 unless ( exists( $unique_terms{ $term } ) );

            # Term limit reached
            ++$terms_analysed;
            if ( $term_limit != 0 )
            {
                last if ( $terms_analysed >= $term_limit );
            }
        }

        $db->dbh->do( "COPY temp_term_counts (term) FROM STDIN" );
        while ( ( $term, $i ) = each( %unique_terms ) )
        {
            $db->dbh->pg_putcopydata( encode_utf8( $term ) . "\n" );
        }

        $db->dbh->pg_putcopyend();
    }

    return $story_count
}

# Inverse Document Frequency (IDF)
sub gen_inverse_document_frequency
{
    my ( $db, $term_limit, $sentence_limit, $stoplist_threshold ) = @_;

    # Read stories (documents), generate the temporary term table
    my $story_count = _fill_temp_table_for_idf($db, $term_limit, $sentence_limit);

    # Print term count
    my $term_count_rs = $db->query(
        "SELECT
                                    term,
                                    LOG($story_count / COUNT(term)) AS idf
                                  FROM temp_term_counts
                                  GROUP BY term
                                  ORDER BY idf ASC
                                  LIMIT $stoplist_threshold"
    );
    binmode( STDERR, ":utf8" );
    while ( my $term_count = $term_count_rs->hash() )
    {
        printf STDERR "%s\t%f\n", $term_count->{ term }, $term_count->{ idf };
    }

    # Cleanup
    $db->query( "DROP TABLE temp_term_counts" );
}

# Normalised Inverse Document Frequency (normalised IDF)
sub gen_normalised_inverse_document_frequency
{
    my ( $db, $term_limit, $sentence_limit, $stoplist_threshold ) = @_;

    # Read stories (documents), generate the temporary term table
    my $story_count = _fill_temp_table_for_idf($db, $term_limit, $sentence_limit);

    # Print term count
    my $term_count_rs = $db->query(
        "SELECT
                                    term,
                                    LOG((($story_count - COUNT(term)) + 0.5) / (COUNT(term) + 0.5)) AS nidf
                                  FROM temp_term_counts
                                  GROUP BY term
                                  ORDER BY nidf ASC
                                  LIMIT $stoplist_threshold"
    );
    binmode( STDERR, ":utf8" );
    while ( my $term_count = $term_count_rs->hash() )
    {
        printf STDERR "%s\t%f\n", $term_count->{ term }, $term_count->{ nidf };
    }

    # Cleanup
    $db->query( "DROP TABLE temp_term_counts" );
}

# Term-based Random Sampling
sub gen_term_based_sampling
{
    print "Not implemented.\n";    # FIXME
}

# FIXME:comment
sub main
{
    my $generation_type    = 'tf';                              # which method of stoplist generation should be used
    my @valid_types        = ( 'tf', 'idf', 'nidf', 'tbrs' );
    my $term_limit         = 0;                                 # how many terms (words) to take into account
    my $sentence_limit     = 4000;                              # how many sentences to take into account
    my $stoplist_threshold = 20;                                # how many stopwords to print

    my Readonly $usage =
      'Usage: ./mediawords_generate_stopwords.pl' . ' [--type=tf|idf|nidf|tbrs]' . ' [--term_limit=i]' .
      ' [--sentence_limit=i]' . ' [--stoplist_threshold=i]';

    GetOptions(
        'type=s'               => \$generation_type,
        'term_limit=i'         => \$term_limit,
        'sentence_limit=i'     => \$sentence_limit,
        'stoplist_threshold=i' => \$stoplist_threshold,
    ) or die "$usage\n";
    die "$usage\n" unless ( grep { $_ eq $generation_type } @valid_types );
    die "Stoplist threshold can not be 0.\n" unless ( $stoplist_threshold != 0 );

    print STDERR "starting --  " . localtime() . "\n";

    my $db = MediaWords::DB::connect_to_db() || die DBIx::Simple::MediaWords->error;

    if ( $generation_type eq 'tf' ) { gen_term_frequency( $db, $term_limit, $sentence_limit, $stoplist_threshold ); }
    elsif ( $generation_type eq 'idf' )
    {
        gen_inverse_document_frequency( $db, $term_limit, $sentence_limit, $stoplist_threshold );
    }
    elsif ( $generation_type eq 'nidf' )
    {
        gen_normalised_inverse_document_frequency( $db, $term_limit, $sentence_limit, $stoplist_threshold );
    }
    elsif ( $generation_type eq 'tbrs' )
    {
        gen_term_based_sampling( $db, $term_limit, $sentence_limit, $stoplist_threshold );
    }

    print STDERR "finished --  " . localtime() . "\n";
}

main();
