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
#   * --term_limit -- how many terms (words) to analyze
#   * --stoplist_threshold -- how many suspected stop words to output
#
# Usage:
#
#   ./script/run_with_carton.sh ./script/mediawords_generate_stopwords.pl \
#       [--type=tf|idf|nidf] \
#       [--term_limit=i] \
#       [--stoplist_threshold=i] > ./lib/MediaWords/Languages/resources/custom_stoplist.txt
#
# TODO:
#   http://en.wikipedia.org/wiki/Tf*idf
#   Normalized TF

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
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

# Helper to sort keys in the ascending order
sub _sort_ascending
{
    my ( $key1, $key2 ) = @_;
    $key1 <=> $key2;
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

    #
    # "Term frequency (TF) of the terms in the corpus: In other words, the number of
    # times a certain term appears throughout a specific collection."
    #

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
        chomp();

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
    print $output_handle _stoplist_header( $corpus_name, $language_code, 'Term Frequency (TF)' );

    # Print out the final results
    my $term_count = 0;
    my $term       = 0;
    for (
        my $status = $db_file_counts->seq( $term_count, $term, R_FIRST ) ;
        $status == 0 ;
        $status = $db_file_counts->seq( $term_count, $term, R_NEXT )
      )
    {
        print $output_handle "$term\t# term count -- $term_count\n";

        ++$x;
        if ( $x >= $stoplist_threshold )
        {
            last;
        }
    }

    say STDERR "Done.";
}

# Create and return a unique terms array for the story
sub _unique_terms_in_story($$)
{
    my ( $story, $lang ) = @_;

    my %unique_terms;

    my $terms = $lang->tokenize( $story );

    for ( my $i = 0 ; $i <= $#$terms ; $i++ )
    {
        my $term = $terms->[ $i ];
        if ( length( $term ) == 0 or length( $term ) > $lang->get_word_length_limit() or looks_like_number( $term ) )
        {
            next;
        }

        $unique_terms{ $term } = 1;
    }

    return keys( %unique_terms );
}

# Create and return story count and reference to 'term' => 'number_of_stories_term_appears_in' hash
sub _count_number_or_stories_terms_appear_in($$$$)
{
    my ( $lang, $input_handle, $story_separator, $term_limit ) = @_;

    # Create a temporary disk storage for keeping 'term' => 'number_of_stories_term_appears_in' pairs
    my %db_terms;
    my $temp_storage = _get_temp_file();
    my $db_file_terms = tie %db_terms, "DB_File", $temp_storage, O_RDWR | O_CREAT, 0666, $DB_BTREE
      or die "Cannot open file '$temp_storage': $!\n";
    $db_file_terms->Filter_Push( 'utf8' );

    # Variable for concatenating a story
    my $story = '';

    # Total number of documents (stories)
    my $story_count = 0;

    # Number of analysed unique terms
    my $analysed_terms   = 0;
    my $progress_modulus = 1000;

    # Count the stories, create the 'term' => 'number_of_stories_term_appears_in' hash
    while ( <$input_handle> )
    {
        chomp;
        my $line = decode_utf8( $_ );

        if ( $analysed_terms != 0 and ( $analysed_terms % 1000 < $progress_modulus ) )
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

        $progress_modulus = $analysed_terms % 1000;

        if ( $line ne $story_separator )
        {
            $story .= $line . ' ';

            die "Story is 1 MB long, maybe the corpus does not contain separators ($story_separator).\n"
              if ( bytes::length( $story ) > ( 1024 * 1024 ) );
        }
        else
        {

            # We have concatenated a full story
            ++$story_count;
            my @unique_terms = _unique_terms_in_story( $story, $lang );
            $analysed_terms += $#unique_terms + 1;
            foreach my $term ( @unique_terms )
            {
                ++$db_terms{ $term };
            }

            $story = '';
        }

        if ( $term_limit != 0 )
        {
            last if ( $analysed_terms >= $term_limit );
        }
    }

    # Add the last story
    ++$story_count;
    my @unique_terms = _unique_terms_in_story( $story, $lang );
    foreach my $term ( @unique_terms )
    {
        ++$db_terms{ $term };
    }

    return ( $story_count, \%db_terms );
}

# Inverse Document Frequency (IDF)
# (note: term limit actually limits the number of unique terms in a story, not the number of all terms)
sub gen_inverse_document_frequency($$$$$$$$)
{

    #
    # "Inverse Document Frequency (IDF) [12]: Using the term frequency distribution in the collection
    # itself where the IDF value of a given term k is given by:
    #     idf_k = log (NDoc / D_k)
    # where NDoc is the total number of documents in the corpus and D_k is the number of documents
    # containing term k.
    # In other words, infrequently occurring terms have a greater probability of occurring in relevant
    # documents and should be considered as more informative and therefore of more importance in these
    # documents."
    #

    my ( $corpus_name, $language_code, $lang, $input_handle, $output_handle, $story_separator, $term_limit,
        $stoplist_threshold )
      = @_;

    # Get story count, reference to 'term' => 'number_of_stories_term_appears_in' hash
    my ( $story_count, $db_terms ) =
      _count_number_or_stories_terms_appear_in( $lang, $input_handle, $story_separator, $term_limit );

    # Will allow duplicate records (duplicate keys -- term IDFs)
    $DB_BTREE->{ 'flags' } = R_DUP;

    # Will sort in the descending order (biggest term IDF goes first)
    $DB_BTREE->{ 'compare' } = \&_sort_ascending;

    # Create a temporary disk storage for keeping 'term_idf' => 'term' pairs
    my %db_idfs;
    my $temp_storage = _get_temp_file();
    my $db_file_idfs = tie %db_idfs, "DB_File", $temp_storage, O_RDWR | O_CREAT, 0666, $DB_BTREE
      or die "Cannot open file '$temp_storage': $!\n";
    $db_file_idfs->Filter_Push( 'utf8' );

    say STDERR "Sorting terms by IDF...";

    # Copy the term IFDs to the new database while also sorting them
    while ( my ( $term, $number_of_stories_term_appears_in ) = each %{ $db_terms } )
    {
        my $idf = log( $story_count / $number_of_stories_term_appears_in );

        $db_idfs{ $idf } = $term;
    }

    say STDERR "Printing out first $stoplist_threshold terms as a stoplist...";

    my $x = 0;

    # Print out header
    print $output_handle _stoplist_header( $corpus_name, $language_code, 'Inverse Document Frequency (IDF)' );

    # Print out the final results
    my $term_idf = 0;
    my $term     = 0;
    for (
        my $status = $db_file_idfs->seq( $term_idf, $term, R_FIRST ) ;
        $status == 0 ;
        $status = $db_file_idfs->seq( $term_idf, $term, R_NEXT )
      )
    {
        printf $output_handle "%s\t# term IDF -- %f\n", $term, $term_idf;

        ++$x;
        if ( $x >= $stoplist_threshold )
        {
            last;
        }
    }

    say STDERR "Done.";
}

# Normalised Inverse Document Frequency (NIDF)
# (note: term limit actually limits the number of unique terms in a story, not the number of all terms)
sub gen_normalised_inverse_document_frequency($$$$$$$$)
{

    #
    # "Normalised IDF: The most common form of IDF weighting is the one used by Robertson and
    # Sparck-Jones [14], which normalises with respect to the number of documents not containing
    # the term (N Doc − D_k) and adds a constant of 0.5 to both numerator and denominator to
    # moderate extreme values:
    #     idf_kNorm = log ( ( (NDoc - D_k ) + 0.5 ) / ( D_k + 0.5 ) )
    # where NDoc is the total number of documents in the collection and D_k is the number of
    # documents containing term k."
    #

    my ( $corpus_name, $language_code, $lang, $input_handle, $output_handle, $story_separator, $term_limit,
        $stoplist_threshold )
      = @_;

    # Get story count, reference to 'term' => 'number_of_stories_term_appears_in' hash
    my ( $story_count, $db_terms ) =
      _count_number_or_stories_terms_appear_in( $lang, $input_handle, $story_separator, $term_limit );

    # Will allow duplicate records (duplicate keys -- term NIDFs)
    $DB_BTREE->{ 'flags' } = R_DUP;

    # Will sort in the descending order (biggest term NIDF goes first)
    $DB_BTREE->{ 'compare' } = \&_sort_ascending;

    # Create a temporary disk storage for keeping 'term_idf' => 'term' pairs
    my %db_nidfs;
    my $temp_storage = _get_temp_file();
    my $db_file_nidfs = tie %db_nidfs, "DB_File", $temp_storage, O_RDWR | O_CREAT, 0666, $DB_BTREE
      or die "Cannot open file '$temp_storage': $!\n";
    $db_file_nidfs->Filter_Push( 'utf8' );

    say STDERR "Sorting terms by NIDF...";

    # Copy the term NIFDs to the new database while also sorting them
    while ( my ( $term, $number_of_stories_term_appears_in ) = each %{ $db_terms } )
    {
        my $nidf = log(
            ( ( $story_count - $number_of_stories_term_appears_in ) + 0.5 ) / ( $number_of_stories_term_appears_in + 0.5 ) );

        $db_nidfs{ $nidf } = $term;
    }

    say STDERR "Printing out first $stoplist_threshold terms as a stoplist...";

    my $x = 0;

    # Print out header
    print $output_handle _stoplist_header( $corpus_name, $language_code, 'Normalised Inverse Document Frequency (NIDF)' );

    # Print out the final results
    my $term_nidf = 0;
    my $term      = 0;
    for (
        my $status = $db_file_nidfs->seq( $term_nidf, $term, R_FIRST ) ;
        $status == 0 ;
        $status = $db_file_nidfs->seq( $term_nidf, $term, R_NEXT )
      )
    {
        printf $output_handle "%s\t# term NIDF -- %f\n", $term, $term_nidf;

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

    my $corpus_name        = '';                         # Corpus name (to be used in the header)
    my $language_code      = '';                         # Corpus language (to split sentences into words)
    my $generation_type    = '';                         # Which method of stoplist generation should be used
    my @valid_types        = ( 'tf', 'idf', 'nidf' );    # Valid (implemented and enabled) stoplist generation types
    my $input_file         = '-';                        # Input file to read corpus from ('-' for STDIN)
    my $output_file        = '-';                        # Output file to write stopwords to ('-' for STDOUT)
    my $story_separator    = '----------------';         # Delimiter to separate one story (article) from another
    my $term_limit         = 0;                          # How many terms (words) to take into account (0 - no limit)
    my $stoplist_threshold = 1000;                       # How many stopwords to print

    my Readonly $usage =
      "Usage: $0" . ' --corpus_name=corpus-simplewiki-20121129' .
      ' --language=lt' . ' --type=tf|idf|nidf' . ' [--input_file=wikipedia.xml]' . ' [--output_file=corpus.txt]' .
      '[--story_separator=----------------]' . ' [--term_limit=i]' . ' [--stoplist_threshold=i]';

    GetOptions(
        'corpus_name=s'        => \$corpus_name,
        'language=s'           => \$language_code,
        'type=s'               => \$generation_type,
        'input_file'           => \$input_file,
        'output_file'          => \$output_file,
        'story_separator=s'    => \$story_separator,
        'term_limit=i'         => \$term_limit,
        'stoplist_threshold=i' => \$stoplist_threshold,
    ) or die "$usage\n";

    die "$usage\n"
      unless ( $corpus_name
        and $language_code
        and $generation_type
        and $input_file
        and $output_file
        and ( grep { $_ eq $generation_type } @valid_types ) );
    die "Stoplist threshold can't be 0.\n" unless ( $stoplist_threshold != 0 );

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
    elsif ( $generation_type eq 'idf' )
    {
        die "Story separator can't be empty.\n" unless ( $story_separator ne '' );

        gen_inverse_document_frequency( $corpus_name, $language_code, $lang, $input_handle, $output_handle, $story_separator,
            $term_limit, $stoplist_threshold );
    }
    elsif ( $generation_type eq 'nidf' )
    {
        die "Story separator can't be empty.\n" unless ( $story_separator ne '' );

        gen_normalised_inverse_document_frequency( $corpus_name, $language_code, $lang, $input_handle, $output_handle,
            $story_separator, $term_limit, $stoplist_threshold );
    }

    # Cleanup
    close INPUT  unless $input_file eq '-';
    close OUTPUT unless $output_file eq '-';

    say STDERR "finished --  " . localtime();
}

main();
