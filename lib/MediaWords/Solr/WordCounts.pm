package MediaWords::Solr::WordCounts;

=head1 NAME

MediaWords::Solr::WordCounts - handle word counting from solr

=head1 DESCRIPTION

Uses sampling to generate quick word counts from solr queries.

=cut

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;

use Data::Dumper;
use List::Util;
use Readonly;
use URI::Escape;

use MediaWords::Languages::Language;
use MediaWords::Solr::Query;
use MediaWords::Util::IdentifyLanguage;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::Text;

# Max. length of the sentence to tokenize
Readonly my $MAX_SENTENCE_LENGTH => 1024;

# Max. number of times to count a word in a single sentence
Readonly my $MAX_REPEATS_PER_SENTENCE => 3;

# Moose instance fields

has 'q'                         => ( is => 'rw', isa => 'Str' );
has 'fq'                        => ( is => 'rw', isa => 'ArrayRef' );
has 'num_words'                 => ( is => 'rw', isa => 'Int', default => 500 );
has 'sample_size'               => ( is => 'rw', isa => 'Int', default => 1000 );
has 'random_seed'               => ( is => 'rw', isa => 'Int', default => 1 );
has 'ngram_size'                => ( is => 'rw', isa => 'Int', default => 1 );
has 'include_stopwords'         => ( is => 'rw', isa => 'Bool', default => 0 );
has 'include_stats'             => ( is => 'rw', isa => 'Bool', default => 0 );

has 'cached_combined_stopwords' => ( is => 'rw', isa => 'HashRef' );
has 'db' => ( is => 'rw' );

# list of all attribute names that should be exposed as cgi params
sub __get_cgi_param_attributes()
{
    return [ qw(q fq num_words sample_size random_seed ngram_size include_stopwords include_stats) ];
}

# return hash of attributes for use as cgi params
sub _get_cgi_param_hash($)
{
    my ( $self ) = @_;

    my $keys = __get_cgi_param_attributes();

    my $meta = $self->meta;

    my $hash = {};
    map { $hash->{ $_ } = $meta->get_attribute( $_ )->get_value( $self ) } @{ $keys };

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

        $vals = {};
        my $keys = __get_cgi_param_attributes();
        for my $key ( @{ $keys } )
        {
            if ( exists( $cgi_params->{ $key } ) )
            {
                $vals->{ $key } = $cgi_params->{ $key };
            }
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

# Cache merged hashes of stopwords for speed
sub _combine_stopwords($$)
{
    my ( $self, $languages ) = @_;

    unless ( ref( $languages ) eq ref( [] ) )
    {
        die "Languages is not an arrayref.";
    }
    unless ( scalar( @{ $languages } ) > 0 )
    {
        die "Languages should have at least one language set.";
    }

    my $language_lookup   = {};
    my $deduped_languages = [];
    for my $language ( @{ $languages } )
    {
        unless ( $language_lookup->{ $language->language_code() } )
        {
            push( @{ $deduped_languages }, $language );
            $language_lookup->{ $language->language_code() } = 1;
        }
    }

    $languages = $deduped_languages;

    my $language_codes = [];
    foreach my $language ( @{ $languages } )
    {
        push( @{ $language_codes }, $language->language_code() );
    }
    $language_codes = [ sort( @{ $language_codes } ) ];

    my $cache_key = join( '-', @{ $language_codes } );

    unless ( $self->cached_combined_stopwords() )
    {
        $self->cached_combined_stopwords( {} );
    }

    unless ( defined $self->cached_combined_stopwords->{ $cache_key } )
    {
        my $combined_stopwords = {};
        foreach my $language ( @{ $languages } )
        {
            my $stopwords = $language->stop_words_map();
            $combined_stopwords = { ( %{ $combined_stopwords }, %{ $stopwords } ) };
        }

        $self->cached_combined_stopwords->{ $cache_key } = $combined_stopwords;
    }

    return $self->cached_combined_stopwords->{ $cache_key };
}

# expects story_sentence hashes, with a story_language field.
#
# parse the text and return a count of stems and terms in the sentence in the
# following format:
#
# { $stem => { count => $stem_count, terms => { $term => $term_count, ... } } }
#
# if ngram_size is > 1, use the unstemmed phrases of ngram_size as the stems
sub count_stems($$)
{
    my ( $self, $story_sentences ) = @_;

    # Set any duplicate sentences blank
    my $dup_sentences = {};

    # Tokenize each sentence and add count to $words for each token
    my $stem_counts = {};
    for my $story_sentence ( @{ $story_sentences } )
    {
        next unless ( defined( $story_sentence ) );

        my $sentence = $story_sentence->{ 'sentence' };
        next unless ( defined( $sentence ) );

        next if ( $dup_sentences->{ $sentence } );
        $dup_sentences->{ $sentence } = 1;

        # Very long sentences tend to be noise -- html text and the like.
        $sentence = substr( $sentence, 0, $MAX_SENTENCE_LENGTH ) if ( length( $sentence ) > $MAX_SENTENCE_LENGTH );

        # Remove urls so they don't get tokenized into noise
        if ( $sentence =~ m~https?://[^\s]+~i )
        {
            $sentence =~ s~https?://[^\s]+~~gi;
        }

        my $story_language    = $story_sentence->{ 'story_language' } || 'en';
        my $sentence_language = $story_sentence->{ language }         || 'en';

        # Language objects are cached in ::Languages::Language, no need to have a separate cache
        my $lang_en       = MediaWords::Languages::Language::default_language();
        my $lang_story    = MediaWords::Languages::Language::language_for_code( $story_language ) || $lang_en;
        my $lang_sentence = MediaWords::Languages::Language::language_for_code( $sentence_language ) || $lang_en;

        # Tokenize into words
        my $sentence_words = $lang_sentence->split_sentence_to_words( $sentence );

        # Remove stopwords;
        # (don't stem stopwords first as they will usually be stemmed too much)
        my $combined_stopwords = {};
        unless ( $self->include_stopwords )
        {
            # Use both sentence's language and English stopwords
            $combined_stopwords = $self->_combine_stopwords( [ $lang_en, $lang_story, $lang_sentence ] );
        }

        sub _word_is_valid_token($$)
        {
            my ( $word, $stopwords ) = @_;

            # Remove numbers
            if ( $word =~ /^\d+?$/ )
            {
                return 0;
            }

            # Remove stopwords
            if ( $stopwords->{ $word } )
            {
                return 0;
            }

            return 1;
        }

        $sentence_words = [ grep { _word_is_valid_token( $_, $combined_stopwords ) } @{ $sentence_words } ];

        # Stem using sentence language's algorithm
        my $sentence_word_stems =
          ( $self->ngram_size > 1 ) ? $sentence_words : $lang_sentence->stem_words( $sentence_words );

        my $n          = $self->ngram_size;
        my $num_ngrams = scalar( @{ $sentence_words } ) - $n + 1;

        my $sentence_stem_counts = {};

        for ( my $i = 0 ; $i < $num_ngrams ; ++$i )
        {
            my $term = join( ' ', @{ $sentence_words }[ $i ..      ( $i + $n - 1 ) ] );
            my $stem = join( ' ', @{ $sentence_word_stems }[ $i .. ( $i + $n - 1 ) ] );

            $sentence_stem_counts->{ $stem } //= {};
            ++$sentence_stem_counts->{ $stem }->{ count };

            next if ( $sentence_stem_counts->{ $stem }->{ count } > $MAX_REPEATS_PER_SENTENCE );

            $stem_counts->{ $stem } //= {};
            ++$stem_counts->{ $stem }->{ count };

            $stem_counts->{ $stem }->{ terms } //= {};
            ++$stem_counts->{ $stem }->{ terms }->{ $term };
        }
    }

    return $stem_counts;
}

# get sorted list of most common words in sentences matching a Solr query, Excludes stop words.
sub get_words($)
{
    my ( $self ) = @_;

    my $db = $self->db;

    unless ( $self->q() || ( $self->fq && @{ $self->fq } ) )
    {
        return [];
    }

    my $solr_params = {
        q    => $self->q(),
        fq   => $self->fq,
        rows => $self->sample_size,
        sort => 'random_' . $self->random_seed . ' asc'
    };

    DEBUG( "executing solr query ..." );
    DEBUG Dumper( $solr_params );

    my $story_sentences =
      MediaWords::Solr::Query::query_solr_for_matching_sentences( $self->db, $solr_params, $self->sample_size );

    DEBUG( "counting sentences..." );
    my $words = $self->count_stems( $story_sentences );
    DEBUG( "done counting sentences" );

    my @word_list;
    while ( my ( $stem, $count ) = each( %{ $words } ) )
    {
        push( @word_list, { stem => $stem, count => $count->{ count } } );
    }

    @word_list = sort {
        $b->{ count } <=> $a->{ count } or    #
          $b->{ stem } cmp $a->{ stem }       #
    } @word_list;

    my $counts = [];
    for my $w ( @word_list )
    {
        my $terms = $words->{ $w->{ stem } }->{ terms };
        my ( $max_term, $max_term_count );
        while ( my ( $term, $term_count ) = each( %{ $terms } ) )
        {
            if ( !$max_term || ( $term_count > $max_term_count ) )
            {
                $max_term       = $term;
                $max_term_count = $term_count;
            }
        }

        if ( !MediaWords::Util::Text::is_valid_utf8( $w->{ stem } ) || !MediaWords::Util::Text::is_valid_utf8( $max_term ) )
        {
            WARN "invalid utf8: $w->{ stem } / $max_term";
            next;
        }

        push( @{ $counts }, { stem => $w->{ stem }, count => $w->{ count }, term => $max_term } );
    }

    splice( @{ $counts }, $self->num_words );

    if ( $self->include_stats )
    {
        return {
            stats => {
                num_words_returned     => scalar( @{ $counts } ),
                num_sentences_returned => scalar( @{ $story_sentences } ),
                num_words_param        => $self->num_words,
                sample_size_param      => $self->sample_size,
                random_seed            => $self->random_seed
            },
            words => $counts
        };
    }
    else
    {
        return $counts;
    }
}

1;
