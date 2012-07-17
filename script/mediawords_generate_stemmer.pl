#!/usr/bin/env perl

# FIXME:description
#
# Di Nunzio, G.M., Ferro, N., Melucci, M., Orio, N., 2004. Experiments to Evaluate Probabilistic Models
# for Automatic Stemmer Generation and Query Word Translation. Comparative evaluation of multi-lingual
# information access systems, Vol. 3237 of lecture notes in computer science 220–235.
# http://books.google.lt/books?id=JYgg4nIXvhsC&lpg=PA220&ots=jH5MmoUPRc&dq=Experiments%20to%20Evaluate%20Probabilistic%20Models%20for%20Automatic%20Stemmer%20Generation%20and%20Query%20Word%20Translation&hl=lt&pg=PA220#v=onepage&q=Experiments%20to%20Evaluate%20Probabilistic%20Models%20for%20Automatic%20Stemmer%20Generation%20and%20Query%20Word%20Translation&f=false
#
# usage: mediawords_generate_stemmer.pl --term=term
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
use Encode;
use Scalar::Util qw(looks_like_number);

# Check if a PostgreSQL table exists
sub _table_exists
{
    my ( $db, $table_name ) = @_;

    my $table_rs = $db->query(
        " SELECT COUNT(*) AS table_exists
                                FROM information_schema.tables 
                                WHERE
                                    table_catalog = CURRENT_CATALOG AND
                                    table_schema = CURRENT_SCHEMA AND
                                    table_name = '$table_name'"
    );
    return $table_rs->hash()->{ table_exists };
}

# Get an average row count of a table
sub _table_avg_row_count
{
    my ( $db, $table_name ) = @_;

    my $count_rs = $db->query(
        " SELECT n_live_tup AS average_row_count 
                                FROM pg_stat_user_tables 
                                WHERE relname = '$table_name'"
    );
    return $count_rs->hash()->{ average_row_count };
}

# Generate a stemmer
sub generate_stemmer
{
    my ( $db, $term ) = @_;

    $term = Encode::decode_utf8( $term );
    die "Term to be stemmed is empty.\n" unless ( length( $term ) > 0 );

    my Readonly $stemmer_table = 'stemmer_terms';

    # Check if a stemmer table (of unique words) already exists
    my $table_has_to_be_created = 0;
    if ( !_table_exists( $db, $stemmer_table ) )
    {
        print STDERR "Stemmer table '$stemmer_table' does not exist, will create one.\n";
        $table_has_to_be_created = 1;
    }
    else
    {
        if ( _table_avg_row_count( $db, $stemmer_table ) == 0 )
        {
            print STDERR "Stemmer table '$stemmer_table' exists already but is empty, will re-create one.\n";
            $db->query( "DROP TABLE $stemmer_table" );
            $table_has_to_be_created = 1;
        }
        else
        {
            $table_has_to_be_created = 0;
        }
    }

    # Create a stemmer table if needed
    if ( $table_has_to_be_created )
    {

        print STDERR "Creating stemmer table '$stemmer_table'...\n";
        $db->query(
            "CREATE TABLE $stemmer_table (
                        id      SERIAL          PRIMARY KEY,
                        term    VARCHAR(256)    NOT NULL,
                        stem    VARCHAR(256)    NULL
                    )"
        );
        $db->query( "CREATE INDEX ${stemmer_table}_term ON $stemmer_table(term)" );

        print STDERR "Importing unique words to '$stemmer_table'...\n";
        print STDERR "(this might take a lot of time, something around 7 minutes for 34 mil." .
          " rows in 'story_sentence_words', so go get a beverage.)\n";
        $db->query(
            "INSERT INTO $stemmer_table (term)
                        SELECT DISTINCT term
                        FROM story_sentence_words
                        WHERE term NOT SIMILAR TO '%[0-9]%'
                        ORDER BY term"
        );
    }

    my $term_avg_count = _table_avg_row_count( $db, $stemmer_table );
    die "No terms were found in the stemmer table '$stemmer_table'.\n" unless $term_avg_count;
    print STDERR "I have about $term_avg_count terms in the stemmer table.\n";

    binmode( STDERR, ":utf8" );

    # Try to stem a term
    print STDERR "Will attempt to stem a term '$term'.\n";
    for ( my $i = 1 ; $i < length( $term ) ; $i++ )
    {
        my $prefix = substr( $term, 0, $i );
        my $suffix = substr( $term, $i );

        my $prefix_count_rs = $db->query(
            "  SELECT COUNT(id) AS prefix_count
                                            FROM $stemmer_table
                                            WHERE TERM LIKE '${prefix}%'"
        );
        my $prefix_count    = $prefix_count_rs->hash()->{ prefix_count } / $term_avg_count;
        my $suffix_count_rs = $db->query(
            "  SELECT COUNT(id) AS suffix_count
                                            FROM $stemmer_table
                                            WHERE TERM LIKE '%${suffix}'"
        );
        my $suffix_count = $suffix_count_rs->hash()->{ suffix_count } / $term_avg_count;

        my $avg_probability = $prefix_count + $suffix_count - ( $prefix_count * $suffix_count );

        print STDERR "\tprefix: $prefix, suffix: $suffix\n";
        printf STDERR "\t\tprefix count: %f, suffix count: %f, avg. prob.: %f\n", $prefix_count, $suffix_count,
          $avg_probability;
    }
}

# FIXME:comment
sub main
{
    my $term = '';    # term to be stemmed

    my Readonly $usage = 'Usage: ./mediawords_generate_stemmer.pl --term=term';

    GetOptions( 'term=s' => \$term, ) or die "$usage\n";
    die "$usage\n" unless ( length( $term ) );

    print STDERR "starting --  " . localtime() . "\n";

    my $db = MediaWords::DB::connect_to_db() || die DBIx::Simple::MediaWords->error;

    # Generate a stemmer
    generate_stemmer( $db, $term );

    print STDERR "finished --  " . localtime() . "\n";
}

main();
