#!/usr/bin/env perl

# efficiently count stemmed words.

# usage: count_words.pl [--port <port>] [--file <file>]

# default mode is to run as a cgi script.  If --port is specified, run as a standlone server
# on that port.  If --file is specified, count the words for the given file.

package SolrCountServer;

use strict;

use threads qw(stringify);
use threads::shared;

use Data::Dumper;
use Encode;
use Getopt::Long;
use HTTP::Request::Common;
use HTTP::Server::Simple::CGI;
use IO::Socket::INET;
use JSON;
use LWP::UserAgent;
use List::Util;
use URI::Escape;

use base qw(HTTP::Server::Simple::CGI);

# number of lines to process by count_stems at a time
use constant MAX_LINE_BLOCK_SIZE => 500;

# max number of random sentences to fetch
use constant MAX_RANDOM_SENTENCES => 10000;

# number of words to return
use constant NUM_RETURN_WORDS => 500;

# base url for solr searches
use constant SOLR_SELECT_URL => 'http://localhost:8983/solr/collection1/select';

# result cache
my $_cached_word_count_json;

# set any duplicate lines blank.
# if $dup_lines is specified, it is assumed to be shared among threads.  leave if
# you don't want to track duplicates across threads
sub blank_dup_lines
{
    my ( $lines, $dup_lines ) = @_;

    my $threaded = 1;
    if ( $dup_lines )
    {
        $threaded = 1;
    }
    else
    {
        $dup_lines = {};
        $threaded  = 0;
    }

    map {
        $threaded ? lock( $dup_lines ) : undef;
        $dup_lines->{ $_ } ? ( $_ = '' ) : ( $dup_lines->{ $_ } = 1 );
    } @{ $lines };
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
    my ( $lines, $dup_lines ) = @_;

    blank_dup_lines( $lines, $dup_lines );

    # tokenize each line and add count to $words for each token
    my $words = {};
    for my $line ( @{ $lines } )
    {
        # very long lines tend to be noise -- html text and the like.
        # lc here instead of individual word for better performance
        $line = lc( substr( $line, 0, 256 ) );

        # replace anything sequence of not-space-punct characters with a
        # single space so that we can just use a split below for better performance
        # than matching each token as /(\w\w\w+)/; in theory, this could miss
        # control characters and such, but it is much faster than using \w because
        # \w requires encoding the line for extended unicode characters, and encoding
        # is very slow
        $line =~ s/[[:punct:][:space:]]/ /og;

        # split performance much better than a regex match for each word.
        # for some reason, the single map / grep / split line works better
        # than an less concise version with an explicit loop.
        map { $words->{ $_ }++ } grep { length( $_ ) > 2 } split( ' ', $line );
    }

    # now we need to stem the words.  It's faster to stem as a single set of words.  we
    # don't want to use caching with the stemming because we are finding the unique
    # words ourselves.
    my @unique_words = keys( %{ $words } );
    my @stems        = @unique_words;

    # Lingua::Stem::Snowball is an order of magnitude faster than Lingua::Stem,
    # but LSS is not threadsafe unless we wait until we are within a thread
    # to import it
    require Lingua::Stem::Snowball;
    my $stemmer = Lingua::Stem::Snowball->new( lang => 'en' );
    $stemmer->stem_in_place( \@stems );

    my $stem_counts = {};
    for ( my $i = 0 ; $i < @stems ; $i++ )
    {
        $stem_counts->{ $stems[ $i ] }->[ 0 ] += $words->{ $unique_words[ $i ] };
        $stem_counts->{ $stems[ $i ] }->[ 1 ]->{ $unique_words[ $i ] } += $words->{ $unique_words[ $i ] };
    }

    return $stem_counts;
}

# get the count_stem results from the $thread and merge them into the words hash
sub merge_thread_words
{
    my ( $thread, $words ) = @_;

    return unless ( $thread );

    # all defined threads should be running
    die( "thread $thread is not running or joinable" ) unless ( $thread->is_running || $thread->is_joinable );

    # this should block if the thread is not done yet to prevent
    # too many threads from getting started
    my $thread_words = $thread->join();

    for my $stem ( keys( %{ $thread_words } ) )
    {
        next unless ( $stem );

        $words->{ $stem }->{ count } += $thread_words->{ $stem }->[ 0 ]++;

        my $term_stem_counts = $words->{ $stem }->{ terms } ||= {};
        for my $term ( keys( %{ $thread_words->{ $stem }->[ 1 ] } ) )
        {
            $term_stem_counts->{ $term } += $thread_words->{ $stem }->[ 1 ]->{ $term };
        }
    }
}

# execute the query on solr with 0 rows just to get the number
# of sentences to be returned
sub get_num_sentences_from_solr
{
    my ( $q, $fqs ) = @_;

    my $params = get_solr_params_hash( $q, $fqs );

    my $ua = LWP::UserAgent->new();

    $params->{ rows } = 0;
    $params->{ wt }   = 'json';
    $params->{ df }   = 'sentence';

    my $res = $ua->post( SOLR_SELECT_URL, $params );

    die( "error retrieving number of sentences from solr: " . $res->as_string ) unless ( $res->is_success );

    my $json = $res->content;

    my $data = decode_json( $json );

    my $num_found = $data->{ response }->{ numFound };

    die( "Unable to find response->numFound in json: $json" ) unless ( defined( $num_found ) );

    return $num_found;
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

    my $params = { q => $q, fl => 'sentence' };
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

    my $found_csv_header = 0;
    while ( my $line = <$sock> )
    {
        if ( $line =~ /^sentence/i )
        {
            $found_csv_header = 1;
            last;
        }
    }

    die( "Unable to find 'sentence' csv header in solr response" ) unless ( $found_csv_header );
}

# send request to solr and return the number of sentences that will be returned
# and a file handle that we can read for responses
sub get_solr_results_socket
{
    my ( $q, $fqs, $file ) = @_;

    # if a file is specified, just use the file (for eval purposes)
    if ( $file )
    {
        my $fh = FileHandle::new;
        $fh->open( '< ' . $file ) || die( "unable to open $file: $!" );

        advance_past_csv_header( $fh );
        return ( 100000, $fh );
    }

    my $num_sentences = get_num_sentences_from_solr( $q, $fqs );

    my $sock = IO::Socket::INET->new( PeerAddr => 'localhost', PeerPort => '8983', Proto => 'tcp' )
      || die( "Unable to open socket to solr: '$|'" );

    my $params = get_solr_params_hash( $q, $fqs );

    $params->{ rows } = List::Util::min( $num_sentences, MAX_RANDOM_SENTENCES );
    $params->{ wt }   = 'csv';
    $params->{ df }   = 'sentence';
    $params->{ sort } = 'random_1 asc';

    my $full_request = POST( SOLR_SELECT_URL, $params );

    my $request_string = $full_request->as_string;

    my $post = "POST " . SOLR_SELECT_URL;

    # for some reason, the HTTP::Request::as_string method does not include
    # the HTTP protocol id at the end of the HTTP POST line
    $request_string =~ s/^$post/$post HTTP\/1.0/;

    $sock->print( $request_string );

    my $status = <$sock>;
    chomp( $status );
    chomp( $status );

    die( "error requesting data from solr: '$status'" ) unless ( $status =~ m~^HTTP/1.1 200 OK~ );

    advance_past_csv_header( $sock );

    return ( $num_sentences, $sock );
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

# lookup previous result in the cache by the q and fq params
sub get_cached_word_count_json
{
    my ( $q, $fqs ) = @_;

    my $params_list = get_params_list( $q, $fqs );

    return $_cached_word_count_json->{ $params_list };
}

# put result into the cache by the q and fq params
sub put_cached_word_count_json
{
    my ( $q, $fqs, $json ) = @_;

    my $params_list = get_params_list( $q, $fqs );

    $_cached_word_count_json->{ $params_list } = $json;
}

# clear the word count json cache
sub clear_word_count_json_cache
{
    $_cached_word_count_json = {};
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

sub get_solr_word_count_json
{
    my ( $q, $fqs, $file ) = @_;
    print STDERR "generating word hash ...\n";
    print STDERR Dumper( $q, $fqs );

    return encode_json( { words => [] } ) unless ( $q || @{ $fqs } );

    if ( my $cached_json = get_cached_word_count_json( $q, $fqs ) )
    {
        print STDERR "cache hit\n";
        return $cached_json;
    }

    my $start_generation_time = time();

    my $num_threads = 15;
    my $threads     = [];
    my $words       = {};

    my ( $num_sentences, $socket ) = get_solr_results_socket( $q, $fqs, $file );

    print STDERR "found $num_sentences sentences in solr ...\n";

    # sentences is not quite the same as lines, since some sentences might be more than one line, but
    # it's close enough to guess a good line_block_size
    my $line_block_size = $num_sentences / $num_threads;
    $line_block_size = ( $line_block_size > MAX_LINE_BLOCK_SIZE ) ? MAX_LINE_BLOCK_SIZE : $line_block_size;

    # only use each line once
    my ( %dup_lines_hash, $dup_lines ) : shared;
    my $dup_lines = \%dup_lines_hash;

    # start up one thread for each block of lines, start merging the results back into the
    # current thread at $num_threads threads previous to the current thread
    while ( my $lines = get_lines_from_socket( $socket, $line_block_size ) )
    {
        my $thread = threads->create( \&count_stems, $lines, $dup_lines );
        push( @{ $threads }, $thread );

        if ( scalar( @{ $threads } ) > ( $num_threads - 1 ) )
        {
            merge_thread_words( $threads->[ -1 * $num_threads ], $words );
        }
    }

    # merge any still running threads
    map { merge_thread_words( $_, $words ) if ( $_->is_running || $_->is_joinable ) } @{ $threads };

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

    my $json_list = [];
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

        push( @{ $json_list }, { stem => $w->[ 0 ], count => $w->[ 1 ], term => $max_term } );

        #        print STDERR "$max_term\n";
    }

    my $json = to_json( { words => $json_list }, { pretty => 1 } );

    print STDERR "returning json: " . substr( $json, 0, 1024 ) . "\n";
    print STDERR "total generation time: " . ( time() - $start_generation_time ) . "\n";
    print STDERR "thread end time: " . ( $merge_end_time - $start_generation_time ) . "\n";

    put_cached_word_count_json( $q, $fqs, $json );

    return $json;
}

sub handle_request
{
    my ( $self, $cgi ) = @_;

    my %dispatch = (
        '/wc'          => \&wc_page,
        '/wc_form'     => \&wc_form_page,
        '/clear_cache' => \&clear_cache_page
    );

    my $path    = $cgi->path_info();
    my $handler = $dispatch{ $path };

    if ( ref( $handler ) eq "CODE" )
    {
        print "HTTP/1.0 200 OK\r\n";
        $handler->( $cgi );
    }
    else
    {
        print "HTTP/1.0 404 Not found\r\n";
        print $cgi->header, $cgi->start_html( 'Not found' ), $cgi->h1( 'Not found' ), $cgi->end_html;
    }
}

sub wc_form_page
{
    print <<END;
Content-Type: text/html; charset=utf-8

<html>
<head><title>Media Cloud Word Count Query</title></head>
<body>
<h1>Media Cloud Word Count Query</title></h1>
<form action="/wc" method="GET">
Q: <input type="text" size="160" name="q" /><br />
FQ: </label><input type="text" size="160" name="fq" /><br />
<input type="submit" value="go" />
</form>
</body>
</html>
END

}

sub wc_page
{
    my ( $cgi ) = @_;

    my $q   = $cgi->param( 'q' );
    my $fqs = [ $cgi->param( 'fq' ) ];

    my $json = get_solr_word_count_json( $q, $fqs );
    my $json_length = length( $json );

    print <<END;
Content-Type: application/json; charset=utf-8
Content-Length: $json_length

$json
END
}

sub clear_cache_page
{
    my ( $cgi ) = @_;

    clear_word_count_json_cache();

    print <<END;
Content-Type: text/plain; charset=utf-8

The cache has been cleared.
END
}

# start word counting web service
sub main
{
    my ( $port, $file );
    
    Getopt::Long::GetOptions(
        "port=i"    => \$port,
        "file=s"    => \$file
    ) || return;

    if ( $port )
    {
        SolrCountServer->new( $port )->run;
    }
    elsif ( $file )
    {
        my $fh = FileHandle::new;
        $fh->open( '<' . $file ) || die( "cannot open '$file': $!" );
        my $lines = [ <$fh> ];
        my $words = count_stems( $lines );

        print STDERR substr( Dumper( $words ), 0, 1024 ) . "\n";
    }
    else
    {
        count_words
    }
}

main();
