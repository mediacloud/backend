package MediaWords::Solr::WordCounts;

use Moose;

=head1 NAME

MediaWords::Solr::WordCounts - handle word counting from solr

=head1 DESCRIPTION

Uses sampling to generate quick word counts from solr queries.

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use CHI;
use Data::Dumper;
use Encode;
use List::Util;
use Readonly;
use URI::Escape;

use MediaWords::Languages::Language;
use MediaWords::Solr;
use MediaWords::Util::Config;
use MediaWords::Util::IdentifyLanguage;
use MediaWords::Util::JSON;
use MediaWords::Util::Text;

# minimum ratio of sentences in a given language to total sentences for a given query to include
# stopwords and stemming for that language
Readonly my $MIN_LANGUAGE_LEVEL => 0.05;

# Max. length of the sentence to tokenize
Readonly my $MAX_SENTENCE_LENGTH => 1024;

# mediawords.wc_cache_version from config
my $_wc_cache_version;

# Moose instance fields

has 'q'                 => ( is => 'rw', isa => 'Str' );
has 'fq'                => ( is => 'rw', isa => 'ArrayRef' );
has 'num_words'         => ( is => 'rw', isa => 'Int', default => 500 );
has 'sample_size'       => ( is => 'rw', isa => 'Int', default => 1000 );
has 'languages'         => ( is => 'rw', isa => 'ArrayRef' );
has 'language_objects'  => ( is => 'rw', isa => 'ArrayRef' );
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

        if ( exists( $cgi_params->{ l } ) && !exists( $cgi_params->{ languages } ) )
        {
            $cgi_params->{ languages } = $cgi_params->{ l };
        }

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
            if ( exists( $cgi_params->{ $key } ) )
            {
                $vals->{ $key } = $cgi_params->{ $key };
            }
        }

        if ( exists( $cgi_params->{ l } ) && !exists( $cgi_params->{ languages } ) )
        {
            $vals->{ languages } = $cgi_params->{ l };
        }

        if ( $args->{ db } )
        {
            $vals->{ db } = $args->{ db };
        }
    }
    else
    {
        $vals = $args;
    }

    if ( $vals->{ fq } && !ref( $vals->{ fq } ) )
    {
        $vals->{ fq } = [ $vals->{ fq } ];
    }

    $vals->{ fq } ||= [];

    return $class->$orig( $vals );
};

# parse the text and return a count of stems and terms in the sentence in the
# following format:
# { $stem => { count =>  $stem_count, terms => { $term => $term_count, ... } } }
#
# this function is where virtually all of the time in the script is spent, and
# had been carefully tuned, so do not change anything without testing performance
# impacts
sub count_stems
{
    my ( $self, $sentences ) = @_;

    $self->set_language_objects();

    # Set any duplicate sentences blank
    my $dup_sentences = {};
    map { $dup_sentences->{ $_ } ? ( $_ = '' ) : ( $dup_sentences->{ $_ } = 1 ); } grep { defined( $_ ) } @{ $sentences };

    # Tokenize each sentence and add count to $words for each token
    my $words = {};
    for my $sentence ( @{ $sentences } )
    {
        unless ( defined( $sentence ) )
        {
            next;
        }

        # Very long sentences tend to be noise -- html text and the like.
        $sentence = substr( $sentence, 0, $MAX_SENTENCE_LENGTH );

        # lc here instead of individual word for better performance
        $sentence = lc( $sentence );

        # for some reason, encode( 'utf8', $sentence ) does not make \w match unicode letters,
        # but the following does
        Encode::_utf8_on( $sentence );

        # remove urls so they don't get tokenized into noise
        $sentence =~ s~https?://[^\s]+~~g;

        while ( $sentence =~ /(\w+)/g )
        {
            my $word           = $1;
            my $word_no_digits = $word;
            $word_no_digits =~ s/\d//g;

            if ( length( $word_no_digits ) > 2 )
            {
                $words->{ $word }++;
            }
        }
    }

    # now we need to stem the words.  It's faster to stem as a single set of words.  we
    # don't want to use caching with the stemming because we are finding the unique
    # words ourselves.
    my @unique_words = keys( %{ $words } );

    my $stems = $self->stem_in_all_languages( \@unique_words );

    my $stem_counts = {};
    for ( my $i = 0 ; $i < @{ $stems } ; $i++ )
    {
        $stem_counts->{ $stems->[ $i ] }->{ count } += $words->{ $unique_words[ $i ] };
        $stem_counts->{ $stems->[ $i ] }->{ terms }->{ $unique_words[ $i ] } += $words->{ $unique_words[ $i ] };
    }

    $self->prune_stopword_stems( $stem_counts );

    return $stem_counts;
}

# given a list of terms, apply stemming in all languages sequentially, with consistent results
sub stem_in_all_languages
{
    my ( $self, $stems ) = @_;

    my $stems_all_languages = [ @{ $stems } ];

    # sort the languages by code so that the merged stemming will always be consistent
    my $ordered_languages = [ sort { $a->get_language_code cmp $b->get_language_code } @{ $self->language_objects } ];

    map { $stems_all_languages = $_->stem( @{ $stems_all_languages } ) } @{ $ordered_languages };

    return $stems_all_languages;
}

# got the stopwords from all language, stem the stopwords in all languages, then generate a single stop_stems
# lookup hash.  we have to restem all words from all languages to make sure the stemming process of the counted
# words is the same as the stemming process for the stopwords
sub get_stop_stems_in_all_languages
{
    my ( $self ) = @_;

    my $all_stopwords = [];
    for my $language ( @{ $self->language_objects } )
    {
        my $stopwords = $language->get_long_stop_words;
        TRACE "get stop words " . $language->get_language_code . " " . scalar( keys( %{ $stopwords } ) );
        push( @{ $all_stopwords }, keys( %{ $stopwords } ) );
    }

    my $all_stopstems = $self->stem_in_all_languages( $all_stopwords );

    my $stopstems = {};
    map { $stopstems->{ $_ } = 1 } @{ $all_stopstems };

    TRACE "stop stems size: " . scalar( keys( %{ $stopstems } ) );

    return $stopstems;
}

# remove stopwords from the $stem_counts
sub prune_stopword_stems
{
    my ( $self, $stem_counts ) = @_;

    if ( $self->include_stopwords )
    {
        return;
    }

    my $stop_stems = $self->get_stop_stems_in_all_languages();

    for my $stem ( keys( %{ $stem_counts } ) )
    {
        if ( ( length( $stem ) < 3 ) || $stop_stems->{ $stem } )
        {
            delete( $stem_counts->{ $stem } );
        }
    }
}

# guess the languages to be the language of the whole body of text plus all distinct languages for individual sentences.
# if no language is detected for the text of any sentence, default to 'en'.  append these default languages to the
# specified list of languages.
sub set_default_languages($$)
{
    my ( $self, $sentences ) = @_;

    if ( $self->languages && @{ $self->languages } )
    {
        return;
    }

    # our cld language detection mis-identifies english as other languages enough that we should always include 'en'
    my $language_lookup = { 'en' => 1 };

    if ( $self->languages )
    {
        map { $language_lookup->{ $_ } = 1 } @{ $self->languages };
    }

    my $story_text = join( "\n", grep { $_ } @{ $sentences } );
    my $story_language = MediaWords::Util::IdentifyLanguage::language_code_for_text( $story_text );

    $language_lookup->{ $story_language } = 1;

    my $sentence_language_counts = {};
    for my $sentence ( @{ $sentences } )
    {
        my $sentence_language = MediaWords::Util::IdentifyLanguage::language_code_for_text( $sentence );

        if ( $sentence_language )
        {
            $sentence_language_counts->{ $sentence_language }++;
        }
    }

    my $total_sentence_count = scalar( @{ $sentences } );
    while ( my ( $language, $language_count ) = each( %{ $sentence_language_counts } ) )
    {
        if ( ( $language_count / $total_sentence_count ) > $MIN_LANGUAGE_LEVEL )
        {
            $language_lookup->{ $language } = 1;
        }
    }

    my $languages = [ keys( %{ $language_lookup } ) ];

    TRACE "default_languages: " . join( ', ', @{ $languages } );

    $self->languages( $languages );
}

# set langauge_objects to point to a list of MediaWords::Languages::Language objects for each language in
# $self->languages
sub set_language_objects
{
    my ( $self ) = @_;

    if ( $self->language_objects )
    {
        return;
    }

    my $language_objects = [];
    for my $language_code ( @{ $self->languages } )
    {
        my $language_object = MediaWords::Languages::Language::language_for_code( $language_code );

        if ( $language_object )
        {
            push( @{ $language_objects }, $language_object );
        }
    }

    if ( !@{ $language_objects } )
    {
        push( @{ $language_objects }, MediaWords::Languages::Language::language_for_code( 'en' ) );
    }

    $self->language_objects( $language_objects );
}

# given the story_sentences_id in the results, fetch the sentences from postgres
sub _get_sentences_from_solr_results($$)
{
    my ( $self, $solr_data ) = @_;

    my $db = $self->db;

    my $story_sentences_ids = [ map { int( $_->{ story_sentences_id } ) } @{ $solr_data->{ response }->{ docs } } ];

    my $ids_table = $db->get_temporary_ids_table( $story_sentences_ids );

    my $sentences = $db->query( <<SQL )->flat;
select sentence from story_sentences where story_sentences_id in ( select id from $ids_table )
SQL

    return $sentences;
}

# connect to solr server directly and count the words resulting from the query
sub get_words_from_solr_server
{
    my ( $self ) = @_;

    unless ( $self->q() || ( $self->fq && @{ $self->fq } ) )
    {
        return [];
    }

    my $solr_params = {
        q    => $self->q(),
        fq   => $self->fq,
        rows => $self->sample_size,
        fl   => 'story_sentences_id',
        sort => 'random_1 asc'
    };

    DEBUG( "executing solr query ..." );
    DEBUG Dumper( $solr_params );
    my $data = MediaWords::Solr::query( $self->db, $solr_params );

    my $sentences_found = $data->{ response }->{ numFound };
    my $sentences       = $self->_get_sentences_from_solr_results( $data );

    # my @sentences = map { $_->{ sentence } } @{ $data->{ response }->{ docs } };

    $self->set_default_languages( $sentences );

    DEBUG( "counting sentences..." );
    my $words = $self->count_stems( $sentences );

    my @word_list;
    while ( my ( $stem, $count ) = each( %{ $words } ) )
    {
        push( @word_list, [ $stem, $count->{ count } ] );
    }

    @word_list = sort { $b->[ 1 ] <=> $a->[ 1 ] } @word_list;

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

        if ( !MediaWords::Util::Text::is_valid_utf8( $w->[ 0 ] ) || !MediaWords::Util::Text::is_valid_utf8( $max_term ) )
        {
            WARN "invalid utf8: $w->[ 0 ] / $max_term";
            next;
        }

        push( @{ $counts }, { stem => $w->[ 0 ], count => $w->[ 1 ], term => $max_term } );
    }

    splice( @{ $counts }, $self->num_words );

    if ( $self->include_stats )
    {
        return {
            stats => {
                num_words_returned     => scalar( @{ $counts } ),
                num_sentences_returned => scalar( @{ $sentences } ),
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

    unless ( $url && $key )
    {
        return undef;
    }

    my $ua = MediaWords::Util::Web::UserAgent->new();

    $ua->set_timeout( 900 );
    $ua->set_max_size( undef );

    my $uri          = URI->new( $url );
    my $query_params = $self->get_cgi_param_hash;

    $query_params->{ no_remote } = 1;
    $query_params->{ key }       = $key;

    $uri->query_form( $query_params );

    my $res = $ua->get( $uri, Accept => 'application/json' );

    unless ( $res->is_success )
    {
        die( "error retrieving words from solr: " . $res->as_string );
    }

    my $words = MediaWords::Util::JSON::decode_json( $res->decoded_content );

    unless ( $words && ref( $words ) )
    {
        die( "Unable to parse json" );
    }

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
        depth            => 4
    );
}

# return key that uniquely identifies the query
sub _get_cache_key
{
    my ( $self ) = @_;

    $_wc_cache_version //= MediaWords::Util::Config::get_config->{ mediawords }->{ wc_cache_version } || '1';

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

    if ( $words )
    {
        return $words;
    }

    unless ( $self->no_remote )
    {
        $words = $self->_get_remote_words;
    }

    $words ||= $self->get_words_from_solr_server;

    $self->_set_cached_words( $words );

    return $words;
}

1;
