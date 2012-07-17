#!/usr/bin/env perl

# FIXME:description
#
# Valid types:
#   tf -- Term frequency (TF) (default)
#   ntf -- Normalised term frequency (normalised TF)
#   idf -- Inverse Document Frequency (IDF)
#   nidf -- Normalised Inverse Document Frequency (normalised IDF)
#   tbrs -- Term-based Random Sampling
#
# usage: mediawords_generate_stopwords.pl [--type=tf|ntf|idf|nidf|tbrs]
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
    my ( $db ) = @_;

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
    my $sentence_count = $db->query(
        "SELECT reltuples
                                      FROM pg_class
                                      WHERE relname = 'story_sentences'"
    )->hash()->{ reltuples };
    die "Sentence count is 0.\n" unless $sentence_count;
    printf STDERR "Will go through ~%d sentences.\n", $sentence_count;

    # FIXME arbitrary limit
    my $sentences_rs = $db->query( "SELECT sentence FROM story_sentences ORDER BY story_sentences_id LIMIT 2500" );
    my $count        = 0;
    while ( my $sentence = $sentences_rs->hash() )
    {
        if ( ++$count % 1000 == 0 )
        {
            printf STDERR "Tokenizing sentence %d out of ~%d...\n", $count, $sentence_count;
        }

        my $terms = MediaWords::StoryVectors::tokenize( [ $sentence->{ sentence } ] );

        $db->dbh->do( "COPY temp_term_counts (term) FROM STDIN" );
        for ( my $i = 0 ; $i < $#$terms ; $i++ )
        {
            my $term = $terms->[ $i ];
            if ( length( $term ) > 256 )
            {

                # Probably not a word anyway.
                continue;
            }

            $db->dbh->pg_putcopydata( encode_utf8( $term ) . "\n" );
        }
        $db->dbh->pg_putcopyend();

    }

    # Print term count
    # FIXME arbitrary limit
    my $term_count_rs = $db->query(
        "SELECT
                                    term,
                                    COUNT(term) AS term_count
                                  FROM temp_term_counts
                                  GROUP BY term
                                  ORDER BY term_count DESC
                                  LIMIT 20"
    );
    print STDERR "\nTERM COUNT:\n\tterm\tcount\n";
    binmode( STDERR, ":utf8" );
    while ( my $term_count = $term_count_rs->hash() )
    {
        printf STDERR "\t%s\t%d\n", $term_count->{ term }, $term_count->{ term_count };
    }
    print STDERR "\n";

    # Cleanup
    $db->query( "DROP TABLE temp_term_counts" );

}

# Normalised term frequency (normalised TF)
sub gen_normalised_term_frequency
{
    print "Not implemented.\n";    # FIXME
}

# Inverse Document Frequency (IDF)
sub gen_inverse_document_frequency
{
    print "Not implemented.\n";    # FIXME
}

# Normalised Inverse Document Frequency (normalised IDF)
sub gen_normalised_inverse_document_frequency
{
    print "Not implemented.\n";    # FIXME
}

# Term-based Random Sampling
sub gen_term_based_sampling
{
    print "Not implemented.\n";    # FIXME
}

# FIXME:comment
sub main
{
    my $generation_type = 'tf';                                 # default -- Term frequency (TF)
    my @valid_types = ( 'tf', 'ntf', 'idf', 'nidf', 'tbrs' );

    my Readonly $usage = 'USAGE: ./mediawords_generate_stopwords.pl [--type=tf|ntf|idf|nidf|tbrs]';

    GetOptions( 'type=s' => \$generation_type ) or die "$usage\n";
    if ( !grep { $_ eq $generation_type } @valid_types )
    {
        die "$usage\n";
    }

    print STDERR "starting --  " . localtime() . "\n";

    my $db = MediaWords::DB::connect_to_db() || die DBIx::Simple::MediaWords->error;

    if    ( $generation_type eq 'tf' )   { gen_term_frequency( $db ); }
    elsif ( $generation_type eq 'ntf' )  { gen_normalised_term_frequency( $db ); }
    elsif ( $generation_type eq 'idf' )  { gen_inverse_document_frequency( $db ); }
    elsif ( $generation_type eq 'nidf' ) { gen_normalised_inverse_document_frequency( $db ); }
    elsif ( $generation_type eq 'tbrs' ) { gen_term_based_sampling( $db ); }

    print STDERR "finished --  " . localtime() . "\n";
}

main();
