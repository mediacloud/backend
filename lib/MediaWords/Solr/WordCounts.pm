package MediaWords::Solr::WordCounts;

#
# Handle word counting from Solr
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

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

# Default parameter values
Readonly my $DEFAULT_SAMPLE_SIZE       => 1000;
Readonly my $DEFAULT_NGRAM_SIZE        => 1;
Readonly my $DEFAULT_INCLUDE_STOPWORDS => 0;
Readonly my $DEFAULT_NUM_ROWS          => 500;
Readonly my $DEFAULT_RANDOM_SEED       => 1;
Readonly my $DEFAULT_INCLUDE_STATS     => 0;

sub new($;$$)
{
    my ( $class, $ngram_size, $include_stopwords ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->{ _ngram_size }        = $ngram_size        // $DEFAULT_NGRAM_SIZE + 0;
    $self->{ _include_stopwords } = $include_stopwords // $DEFAULT_INCLUDE_STOPWORDS + 0;

    # Combined stopword cache
    $self->{ _cached_combined_stopwords } = {};

    return $self;
}

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

    unless ( defined $self->{ _cached_combined_stopwords }->{ $cache_key } )
    {
        my $combined_stopwords = {};
        foreach my $language ( @{ $languages } )
        {
            my $stopwords = $language->stop_words_map();
            $combined_stopwords = { ( %{ $combined_stopwords }, %{ $stopwords } ) };
        }

        $self->{ _cached_combined_stopwords }->{ $cache_key } = $combined_stopwords;
    }

    return $self->{ _cached_combined_stopwords }->{ $cache_key };
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
        unless ( $self->{ _include_stopwords } )
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
          ( $self->{ _ngram_size } > 1 ) ? $sentence_words : $lang_sentence->stem_words( $sentence_words );

        my $n          = $self->{ _ngram_size };
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
sub get_words($$$$;$$$)
{
    my ( $self, $db, $q, $fq, $sample_size, $num_words, $random_seed, $include_stats ) = @_;

    if ( $fq )
    {
        unless ( ref( $fq ) )
        {
            $fq = [ $fq ];
        }
    }
    else
    {
        $fq = [];
    }

    unless ( defined $sample_size )
    {
        $sample_size = $DEFAULT_SAMPLE_SIZE + 0;
    }
    unless ( defined $num_words )
    {
        $num_words = $DEFAULT_NUM_ROWS + 0;
    }
    unless ( defined $random_seed )
    {
        $random_seed = $DEFAULT_RANDOM_SEED + 0;
    }
    unless ( defined $include_stats )
    {
        $include_stats = $DEFAULT_INCLUDE_STATS + 0;
    }

    unless ( $q or ( $fq and @{ $fq } ) )
    {
        return [];
    }

    my $solr_params = {
        q    => $q,
        fq   => $fq,
        rows => $sample_size,
        sort => 'random_' . $random_seed . ' asc'
    };

    DEBUG( "executing solr query ..." );
    DEBUG Dumper( $solr_params );

    my $story_sentences = MediaWords::Solr::Query::query_solr_for_matching_sentences( $db, $solr_params, $sample_size );

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

    splice( @{ $counts }, $num_words );

    if ( $include_stats )
    {
        return {
            stats => {
                num_words_returned     => scalar( @{ $counts } ),
                num_sentences_returned => scalar( @{ $story_sentences } ),
                num_words_param        => $num_words,
                sample_size_param      => $sample_size,
                random_seed            => $random_seed
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
