#!/usr/bin/env perl
#
# This is an automatic stop word list generator (a stoplist generator) for the Media Cloud project.
#
# You can use it if you don't have a stop word list for your language, or if you want to update
# the stoplist with whatever words are in the database (so that the stoplist would follow the "trends"
# of the websites that are crawled my Media Cloud).
#
# Algorithms described in:
#
#   Makrehchi, M., Kamel, M.S., 2008. Automatic extraction of domain-specific stopwords from labeled
#   documents, in: ECIR’08 Proceedings of the IR Research, ECIR’08. Presented at the 30th European
#   conference on Advances in information retrieval, Springer-Verlag, Glasgow, UK, pp. 222–233.
#   http://terrierteam.dcs.gla.ac.uk/publications/rtlo_DIRpaper.pdf
#
# Parameters:
#
#   * --type -- stoplist generation type (method). Valid types:
#       * tf -- Term frequency (TF)
#       * idf -- Inverse Document Frequency (IDF)
#       * nidf -- Normalised Inverse Document Frequency (normalised IDF)
#       * tbrs -- Term-based Random Sampling
#   * --term_limit -- how many terms (words) to analyze
#   * --stoplist_threshold -- how many suspected stop words to output
#   * --tbrs_iterations -- when using the Term Based Random Sampling, how many iterations of the algorithm to execute
#
# Usage:
#
#   ./script/run_with_carton.sh ./script/mediawords_generate_stopwords.pl \
#       [--type=tf|idf|nidf|tbrs] \
#       [--term_limit=i] \
#       [--stoplist_threshold=i] \
#       [--tbrs_iterations=i] > ./lib/MediaWords/Languages/resources/custom_stoplist.txt
#
# TODO:
#   http://en.wikipedia.org/wiki/Tf*idf

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use utf8;

use Getopt::Long;
use MediaWords::Languages::Language;
use Encode;
use Scalar::Util qw(looks_like_number);
use POSIX qw/strftime/;

use DB_File;
use DBM_Filter;
use File::Temp qw/ tempdir /;

# Return a logarithm value of the number
sub _log_base
{
    my ( $base, $value ) = @_;
    return log( $value ) / log( $base );
}

# Return a string that is appended to the generator's output as a header
sub _stoplist_header
{
    my ( $corpus_name, $language, $generation_type ) = @_;
    my $date_time = strftime( '%d-%b-%Y %H:%M', localtime );

    my $header = '';
    $header .= "#\n";
    $header .= "# This is a stop word list generated from corpus \"$corpus_name\" (language: $language).\n";
    $header .= "#\n";
    $header .= "# The list was generated on $date_time using the \"$generation_type\" method.\n";
    $header .= "#\n";
    $header .= "# The encoding of this file is UTF-8.\n";
    $header .= "#\n";
    $header .= "# To use the list, place it in lib/MediaWords/Languages/resources/ and configure\n";
    $header .= "# your language plug-in accordingly.\n";
    $header .= "#\n";
    $header .= "\n";

    return $header;
}

# Return a path to a temporary file
sub _get_temp_file
{
    my $dir = tempdir( CLEANUP => 1 );
    my $filename = $dir . '/tempfile';

    # say STDERR "Will write to temporary file '$filename'.";

    return $filename;
}

# Helper to sort keys in the descending order
sub _sort_descending
{
    my ( $key1, $key2 ) = @_;
    $key2 <=> $key1;
}

# Term frequency (TF)
sub gen_term_frequency($$$$$$$)
{
    my ( $corpus_name, $language_code, $lang, $input_handle, $output_handle, $term_limit, $stoplist_threshold ) = @_;

    say STDERR "Creating term -> term_count storage...";

    # Create a temporary disk storage for keeping 'term' => 'term_count' pairs
    my %db_terms;
    my $temp_storage = _get_temp_file();
    my $db_file_terms = tie %db_terms, "DB_File", $temp_storage, O_RDWR | O_CREAT, 0666, $DB_BTREE
      or die "Cannot open file '$temp_storage': $!\n";
    $db_file_terms->Filter_Push( 'utf8' );

    my $analysed_terms = 0;
    my $skipped_terms  = 0;

    say STDERR "Adding terms from input source...";

    # Create a temporary data store with term counts ('term' => 'term_count')
    while ( <$input_handle> )
    {
        my $line  = decode_utf8( $_ );
        my $terms = $lang->tokenize( $line );

        for ( my $i = 0 ; $i <= $#$terms ; $i++ )
        {
            if ( $analysed_terms != 0 and $analysed_terms % 1000 == 0 )
            {
                if ( $term_limit != 0 )
                {
                    say STDERR 'Adding term ' . $analysed_terms . '/' . $term_limit . '...';
                }
                else
                {
                    say STDERR 'Adding term ' . $analysed_terms . '...';
                }
            }

            my $term = $terms->[ $i ];
            if ( length( $term ) == 0 or length( $term ) > $lang->get_word_length_limit() or looks_like_number( $term ) )
            {
                ++$skipped_terms;
                next;
            }

            ++$analysed_terms;
            ++$db_terms{ $term };
        }

        if ( $term_limit != 0 )
        {
            last if ( $analysed_terms >= $term_limit );
        }
    }

    say STDERR "Terms added: $analysed_terms; terms skipped (empty, numeric, too long): $skipped_terms.";

    #
    # Sort the terms by copying them to another DB_File database
    # (AFAIK, there's no way to sort the records in the DB_File database above by value,
    # and Perl's sort() capabilities would require fetching a list of terms into memory)
    #

    say STDERR "Creating term_count -> term storage...";

    # Will allow duplicate records (duplicate keys -- term counts)
    $DB_BTREE->{ 'flags' } = R_DUP;

    # Will sort in the descending order (biggest term count goes first)
    $DB_BTREE->{ 'compare' } = \&_sort_descending;

    # Create a temporary disk storage for keeping 'term_count' => 'term' pairs
    my %db_counts;
    $temp_storage = _get_temp_file();
    my $db_file_counts = tie %db_counts, "DB_File", $temp_storage, O_RDWR | O_CREAT, 0666, $DB_BTREE
      or die "Cannot open file '$temp_storage': $!\n";
    $db_file_counts->Filter_Push( 'utf8' );

    say STDERR "Sorting terms by count...";

    # Copy the term counts to the new database while also sorting them
    while ( my ( $term, $term_count ) = each %db_terms )
    {
        $db_counts{ $term_count } = $term;
    }

    say STDERR "Printing out first $stoplist_threshold terms as a stoplist...";

    my $x = 0;

    # Print out header
    print _stoplist_header( $corpus_name, $language_code, 'Term Frequency (TF)' );

    # Print out the final results
    my $term_count = 0;
    my $term       = 0;
    for (
        my $status = $db_file_counts->seq( $term_count, $term, R_FIRST ) ;
        $status == 0 ;
        $status = $db_file_counts->seq( $term_count, $term, R_NEXT )
      )
    {
        print "$term\t# term count -- $term_count\n";

        ++$x;
        if ( $x >= $stoplist_threshold )
        {
            last;
        }
    }

    say STDERR "Done.";
}

# SIGINT (Ctrl+C) handler -- prints out stopwords collected so far
sub INT_handler
{
    say STDERR "aborted --  " . localtime();
    exit( 0 );
}

# SIGINT (Ctrl+C) events will be handled by subroutine 'INT_handler'
# (If you would like to disable this behaviour, comment out the line above)
$SIG{ 'INT' } = 'INT_handler';

# Stoplist generator
sub main
{
    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    my $corpus_name        = '';                                 # Corpus name (to be used in the header)
    my $language_code      = '';                                 # Corpus language (to split sentences into words)
    my $generation_type    = '';                                 # Which method of stoplist generation should be used
    my @valid_types        = ( 'tf', 'idf', 'nidf', 'tbrs' );    # Valid (implemented and enabled) stoplist generation types
    my $input_file         = '-';                                # Input file to read corpus from ('-' for STDIN)
    my $output_file        = '-';                                # Output file to write stopwords to ('-' for STDOUT)
    my $term_limit         = 0;                                  # How many terms (words) to take into account (0 - no limit)
    my $stoplist_threshold = 20;                                 # How many stopwords to print
    my $tbrs_iterations    = 20;                                 # How many times to repeat the TBRS sampling

    my Readonly $usage =
      "Usage: $0" . ' --corpus_name=corpus-simplewiki-20121129' . ' --language=lt' . ' --type=tf|idf|nidf|tbrs' .
      ' [--input_file=wikipedia.xml]' . ' [--output_file=corpus.txt]' . ' [--term_limit=i]' . ' [--stoplist_threshold=i]' .
      ' [--tbrs_iterations=i]';

    GetOptions(
        'corpus_name=s'        => \$corpus_name,
        'language=s'           => \$language_code,
        'type=s'               => \$generation_type,
        'input_file'           => \$input_file,
        'output_file'          => \$output_file,
        'term_limit=i'         => \$term_limit,
        'stoplist_threshold=i' => \$stoplist_threshold,
        'tbrs_iterations=i'    => \$tbrs_iterations,
    ) or die "$usage\n";

    die "$usage\n"
      unless ( $corpus_name
        and $language_code
        and $generation_type
        and $input_file
        and $output_file
        and ( grep { $_ eq $generation_type } @valid_types ) );
    die "Stoplist threshold can't be 0.\n" unless ( $stoplist_threshold != 0 );
    die "TBRS iterations can't be 0.\n"    unless ( $tbrs_iterations != 0 );

    say STDERR "starting --  " . localtime();

    # Load language for tokenizing sentences -> words
    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    die "Unsupported language '$language_code'.\n" unless ( $lang );

    # Input file or STDIN
    if ( $input_file ne '-' )
    {
        open( INPUT, '<', $input_file ) or die $!;
    }
    else
    {
        *INPUT = *STDIN;
    }

    # Output file or STDOUT
    if ( $output_file ne '-' )
    {
        open( OUTPUT, '>', $output_file ) or die $!;
    }
    else
    {
        open( OUTPUT, '>&', \*STDOUT ) or die $!;
    }

    binmode( OUTPUT, ":utf8" );

    my $input_handle  = \*INPUT;
    my $output_handle = \*OUTPUT;

    # Generate stopwords
    if ( $generation_type eq 'tf' )
    {
        gen_term_frequency( $corpus_name, $language_code, $lang, $input_handle, $output_handle, $term_limit,
            $stoplist_threshold );
    }

    # Cleanup
    close INPUT  unless $input_file  eq '-';
    close OUTPUT unless $output_file eq '-';

    say STDERR "finished --  " . localtime();
}

main();
