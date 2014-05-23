package MediaWords::Solr::WordCounts;

# handle direct word counting from solr server results.

# this is written separately from MediaWords::Solr::count_words so that this
# code can run on the solr server itself and be requested over http by
# MediaWords::Solr::count_words.

use strict;

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
            $words->{ $1 }++ if ( length( $1 ) > 2 );
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

# get params string from $q and $fqs arguments
sub get_params_list
{
    my ( $q, $fqs ) = @_;

    my $params = [ "q=" . uri_escape( $q ) ];
    for my $fq ( @{ $fqs } )
    {
        push( @{ $params }, 'fq=' . uri_escape( $fq ) );
    }

    # keep the sort here so that we get consistent hash lookups
    # regardless of the specified order of the arguments
    return join( '&', sort @{ $params } );
}

sub get_solr_params_hash
{
    my ( $q, $fqs ) = @_;

    my $params;

    $params->{ q }                  = $q;
    $params->{ fl }                 = 'sentence';
    $params->{ defType }            = 'edismax';
    $params->{ stopwords }          = 'false';
    $params->{ lowercaseOperators } = 'true';

    $fqs ||= [];
    $fqs = [ $fqs ] unless ( ref( $fqs ) );
    for my $fq ( @{ $fqs } )
    {
        push( @{ $params->{ fq } }, $fq );
    }

    return $params;
}

# advance the socket to the line after the 'sentence' line, which is the csv header
sub advance_past_csv_header
{
    my ( $sock ) = @_;

    my $header           = '';
    my $found_csv_header = 0;
    for ( my $i = 0 ; $i < MAX_HEADER_LINES ; $i++ )
    {
        my $line = <$sock>;
        if ( $line =~ /^sentence/i )
        {
            $found_csv_header = 1;
            last;
        }
        $header .= $line;
    }

    die( "Unable to find 'sentence' csv header in solr response: $header" ) unless ( $found_csv_header );
}

# send request to solr and return a file handle that we can read for responses
sub get_solr_results_socket
{
    my ( $q, $fqs, $file ) = @_;

    # if a file is specified, just use the file (for eval purposes)
    if ( $file )
    {
        my $fh = FileHandle::new;
        $fh->open( '< ' . $file ) || die( "unable to open $file: $!" );

        advance_past_csv_header( $fh );
        return $fh;
    }

    my $url = MediaWords::Solr::get_solr_select_url;

    die( "mediawords:solr_select_url not found in config" ) unless ( $url );

    my $uri  = URI->new( $url );
    my $host = $uri->host;
    my $port = $uri->port;

    # use manual socket to fetch http results so that we can process results as they
    # come in, which is not easy to do with LWP
    my $sock = IO::Socket::INET->new( PeerAddr => $host, PeerPort => $port, Proto => 'tcp' )
      || die( "Unable to open socket to solr: '$|'" );

    my $params = get_solr_params_hash( $q, $fqs );

    $params->{ rows } = MAX_RANDOM_SENTENCES;
    $params->{ wt }   = 'csv';
    $params->{ df }   = 'sentence';
    $params->{ sort } = 'random_1 asc';

    my $full_request = POST( $url, $params );

    my $request_string = $full_request->as_string;

    my $post = "POST $url";

    # for some reason, the HTTP::Request::as_string method does not include
    # the HTTP protocol id at the end of the HTTP POST line
    $request_string =~ s/^$post/$post HTTP\/1.0/;

    $sock->print( $request_string );

    my $status = <$sock>;
    chomp( $status );
    chomp( $status );

    die( "error requesting data from solr: '$status'" ) unless ( $status =~ m~^HTTP/1.1 200 OK~ );

    advance_past_csv_header( $sock );

    return $sock;
}

# get $line_block_size new lines from the socket
sub get_lines_from_socket
{
    my ( $socket, $line_block_size ) = @_;

    my $lines = [];
    while ( ( @{ $lines } < $line_block_size ) && ( my $line = <$socket> ) )
    {
        push( @{ $lines }, $line );
    }

    return @{ $lines } ? $lines : undef;
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

    my $socket = get_solr_results_socket( $q, $fqs, $file );

    my $line_block_size = 500;
    my $dup_lines       = {};
    my $words           = {};

    # grab a block of lines at a time from solr, count the stems, and then grab more lines.
    # this lets us do stem counting while solr is generating more results.
    while ( my $lines = get_lines_from_socket( $socket, $line_block_size ) )
    {
        print STDERR "counting block...\n";
        my $block_words = count_stems( $lines, $dup_lines, $languages );
        merge_block_words( $block_words, $words );
    }

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
    my @return_words =
      ( scalar( @word_list ) > NUM_RETURN_WORDS ) ? @word_list[ 0 .. ( NUM_RETURN_WORDS - 1 ) ] : @word_list;

    my $counts = [];
    for my $w ( @return_words )
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

    return get_stopworded_counts( $counts, $languages );
}

1;
