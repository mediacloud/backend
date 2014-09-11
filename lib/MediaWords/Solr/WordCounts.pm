package MediaWords::Solr::WordCounts;

use Moose;

# handle direct word counting from solr server results.

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

# mediawords.wc_cache_version from config
my $_wc_cache_version;

# Moose instance fields

has 'q'                 => ( is => 'rw', isa => 'Str' );
has 'fq'                => ( is => 'rw', isa => 'ArrayRef' );
has 'num_words'         => ( is => 'rw', isa => 'Int', default => 500 );
has 'sample_size'       => ( is => 'rw', isa => 'Int', default => 1000 );
has 'languages'         => ( is => 'rw', isa => 'ArrayRef', default => sub { [ 'en' ] } );
has 'include_stopwords' => ( is => 'rw', isa => 'Bool' );
has 'no_remote'         => ( is => 'rw', isa => 'Bool' );
has 'include_stats'     => ( is => 'rw', isa => 'Bool' );
has 'db' => ( is => 'rw' );

# list of all attribute names that should be exposed as cgi params
sub get_cgi_param_attributes
{
    return [ qw(q fq languages num_words sample_size include_stopwords include_stats no_remote) ];
}

# return hash of attributes for use as cgi params
sub get_cgi_param_hash
{
    my ( $self ) = @_;

    my $keys = get_cgi_param_attributes;

    my $meta = $self->meta;

    my $hash = {};
    map { $hash->{ $_ } = $meta->get_attribute( $_ )->get_value( $self ) } @{ $keys };

    if ( $hash->{ languages } && ref( $hash->{ languages } ) )
    {
        $hash->{ languages } = join( " ", @{ $hash->{ languages } } );
    }

    return $hash;
}

# add support for constructor in this form:
#   WordsCounts->new( cgi_params => $cgi_params )
# where $cgi_params is a hash of cgi params directly from a web request
around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    my $args;
    if ( ref( $_[ 0 ] ) )
    {
        $args = $_[ 0 ];
    }
    elsif ( defined( $_[ 0 ] ) )
    {
        $args = { @_ };
    }
    else
    {
        $args = {};
    }

    my $vals;
    if ( $args->{ cgi_params } )
    {
        my $cgi_params = $args->{ cgi_params };

        $cgi_params->{ languages } = $cgi_params->{ l }
          if ( exists( $cgi_params->{ l } ) && !exists( $cgi_params->{ languages } ) );

        if ( !$cgi_params->{ languages } )
        {
            $cgi_params->{ languages } = [];
        }
        elsif ( !ref( $cgi_params->{ languages } ) )
        {
            $cgi_params->{ languages } = [ split( /[\s,]/, $cgi_params->{ languages } ) ];
        }

        $vals = {};
        my $keys = get_cgi_param_attributes;
        for my $key ( @{ $keys } )
        {
            $vals->{ $key } = $cgi_params->{ $key } if ( exists( $cgi_params->{ $key } ) );
        }

        $vals->{ languages } = $cgi_params->{ l }
          if ( exists( $cgi_params->{ l } ) && !exists( $cgi_params->{ languages } ) );

        $vals->{ db } = $args->{ db } if ( $args->{ db } );
    }
    else
    {
        $vals = $args;
    }

    say STDERR Dumper( $vals );

    $args->{ fq } = [ $args->{ fq } ] if ( $args->{ fq } && !ref( $args->{ fq } ) );

    return $class->$orig( $vals );
};

# set any duplicate lines blank.
sub blank_dup_lines
{
    my ( $self, $lines ) = @_;

    my $dup_lines = {};

    map { $dup_lines->{ $_ } ? ( $_ = '' ) : ( $dup_lines->{ $_ } = 1 ); } grep { defined( $_ ) } @{ $lines };
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
    my ( $self, $lines ) = @_;

    $self->blank_dup_lines( $lines );

    # tokenize each line and add count to $words for each token
    my $words = {};
    for my $line ( @{ $lines } )
    {
        next unless ( defined( $line ) );

        # very long lines tend to be noise -- html text and the like.
        # lc here instead of individual word for better performance
        $line = lc( substr( $line, 0, 256 ) );

        # for some reason, encode( 'utf8', $line ) does not make \w match unicode letters,
        # but the following does
        Encode::_utf8_on( $line );

        # remove urls so they don't get tokenized into noise
        $line =~ s~https?://[^\s]+~~g;

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

    for my $lang ( @{ $self->languages } )
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
sub is_valid_utf8
{
    my ( $self, $s ) = @_;

    my $valid = 1;

    Encode::_utf8_on( $s );

    $valid = 0 unless ( utf8::valid( $s ) );

    Encode::_utf8_off( $s );

    return $valid;
}

# get the count_stem results from one run of count_stems against a block of lines
sub merge_block_words
{
    my ( $self, $block_words, $words ) = @_;

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
    my ( $self, $words ) = @_;

    return $words if ( $self->include_stopwords );

    for my $lang ( @{ $self->languages } )
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
sub get_words_from_solr_server
{
    my ( $self ) = @_;

    $self->languages( [ 'en' ] ) unless ( $self->languages && @{ $self->languages } );

    return [] unless ( $self->q() || ( $self->fq && @{ $self->fq } ) );

    my $start_generation_time = time();

    my $solr_params = {
        q    => $self->q(),
        fq   => $self->fq,
        rows => $self->sample_size,
        fl   => 'sentence',
        sort => 'random_1 asc'
    };

    print STDERR "executing solr query ...\n";
    print STDERR Dumper( $solr_params );
    my $data = MediaWords::Solr::query( $self->db, $solr_params );

    my $sentences_found = $data->{ response }->{ numFound };
    my @sentences = map { $_->{ sentence } } @{ $data->{ response }->{ docs } };

    print STDERR "counting sentences...\n";
    my $block_words = $self->count_stems( \@sentences );

    my $words = {};
    $self->merge_block_words( $block_words, $words );

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
    my $m = ( 1 + @{ $self->languages } );
    my $num_pre_sw_words = ( 1000 * $m ) + ( $self->num_words * $m );

    #splice( @word_list, $num_pre_sw_words );

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

        if ( !$self->is_valid_utf8( $w->[ 0 ] ) || !$self->is_valid_utf8( $max_term ) )
        {
            print STDERR "invalid utf8: $w->[ 0 ] / $max_term\n";
            next;
        }

        push( @{ $counts }, { stem => $w->[ 0 ], count => $w->[ 1 ], term => $max_term } );
    }

    $counts = $self->get_stopworded_counts( $counts, $self->languages );

    splice( @{ $counts }, $self->num_words );

    if ( $self->include_stats )
    {
        return {
            stats => {
                num_words_returned     => scalar( @{ $counts } ),
                num_sentences_returned => scalar( @sentences ),
                num_sentences_found    => $sentences_found,
                num_words_param        => $self->num_words,
                sample_size_param      => $self->sample_size
            },
            words => $counts
        };
    }
    else
    {
        return $counts;
    }
}

# fetch word counts from a separate server
sub _get_remote_words
{
    my ( $self ) = @_;

    my $url = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_wc_url };
    my $key = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_wc_key };
    return undef unless ( $url && $key );

    my $ua = MediaWords::Util::Web::UserAgent();

    $ua->timeout( 900 );
    $ua->max_size( undef );

    my $uri          = URI->new( $url );
    my $query_params = $self->get_cgi_param_hash;

    $query_params->{ no_remote } = 1;
    $query_params->{ key }       = $key;

    $uri->query_form( $query_params );

    my $res = $ua->get( $uri, Accept => 'application/json' );

    die( "error retrieving words from solr: " . $res->as_string ) unless ( $res->is_success );

    my $words = from_json( $res->content, { utf8 => 1 } );

    die( "Unable to parse json" ) unless ( $words && ref( $words ) );

    return $words;
}

# return CHI cache for word counts
sub _get_cache
{
    my $mediacloud_data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    return CHI->new(
        driver           => 'File',
        expires_in       => '1 day',
        expires_variance => '0.1',
        root_dir         => "${ mediacloud_data_dir }/cache/word_counts",
        cache_size       => '1g'
    );
}

# return key that uniquely identifies the query
sub _get_cache_key
{
    my ( $self ) = @_;

    $_wc_cache_version //= MediaWords::Util::Config->get_config->{ mediawords }->{ wc_cache_version } || '1';

    my $meta = $self->meta;

    my $keys = $self->get_cgi_param_attributes;

    my $hash_key = "$_wc_cache_version:" . Dumper( map { $meta->get_attribute( $_ )->get_value( $self ) } @{ $keys } );

    return $hash_key;
}

# get a cached value for the given word count
sub _get_cached_words
{
    my ( $self ) = @_;

    return $self->_get_cache->get( $self->_get_cache_key );
}

# set a cached value for the given word count
sub _set_cached_words
{
    my ( $self, $value ) = @_;

    return $self->_get_cache->set( $self->_get_cache_key, $value );
}

# get sorted list of most common words in sentences matching a solr query.  exclude stop words from the
# long_stop_word list.  assumes english stemming and stopwording for now.
sub get_words
{
    my ( $self ) = @_;

    my $words = $self->_get_cached_words;

    return $words if ( $words );

    $words = $self->_get_remote_words unless ( $self->no_remote );

    $words ||= $self->get_words_from_solr_server;

    $self->_set_cached_words( $words );

    return $words;
}

1;
