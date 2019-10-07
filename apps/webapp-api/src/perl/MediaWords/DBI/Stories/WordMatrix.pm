package MediaWords::DBI::Stories::WordMatrix;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Solr::WordCounts;

# get a postgres cursor that will return the concatenated story_sentences for each of the given stories_ids.  use
# $sentence_separator to join the sentences for each story.
sub _get_story_word_matrix_cursor($$$)
{
    my ( $db, $stories_ids, $sentence_separator ) = @_;

    my $cursor = 'story_text';

    $stories_ids = [ map { int( $_ ) } @{ $stories_ids } ];

    my $ids_table = $db->get_temporary_ids_table( $stories_ids );
    $db->query( <<SQL, $sentence_separator );
declare $cursor cursor for
    select stories_id, language, string_agg( sentence, \$1 ) story_text
        from story_sentences
        where stories_id in ( select id from $ids_table )
        group by stories_id, language
        order by stories_id, language
SQL

    return $cursor;
}

# Given a list of stories_ids, generate a matrix consisting of the vector of word stem counts for each stories_id on each
# line.  Return a hash of story word counts and a list of word stems.
#
# The list of story word counts is in the following format:
# {
#     { <stories_id> =>
#         { <word_id_1> => <count>,
#           <word_id_2 => <count>
#         }
#     },
#     ...
# ]
#
# The id of each word is the indes of the given word in the word list.  The word list is a list of lists, with each
# member list consisting of the stem followed by the most commonly used term.
#
# For example, for stories_ids 1 and 2, both of which contain 4 mentions of 'foo' and 10 of 'bars', the word count
# has and and word list look like:
#
# [ { 1 => { 0 => 4, 1 => 10 } }, { 2 => { 0 => 4, 1 => 10 } } ]
#
# [ [ 'foo', 'foo' ], [ 'bar', 'bars' ] ]
#
# The story_sentences for each story will be used for word counting. If $max_words is specified, only the most common
# $max_words will be used for each story.
#
# The function uses MediaWords::Util::IdentifyLanguage to identify the stemming and stopwording language for each story.
# If the language of a given story is not supported, stemming and stopwording become null operations.  For the list of
# languages supported, see @MediaWords::Langauges::Language::_supported_languages.
sub get_story_word_matrix($$;$)
{
    my ( $db, $stories_ids, $max_words ) = @_;

    my $word_index_lookup   = {};
    my $word_index_sequence = 0;
    my $word_term_counts    = {};

    my $use_transaction = !$db->in_transaction();
    $db->begin if ( $use_transaction );

    my $sentence_separator = 'SPLITSPLIT';
    my $story_text_cursor = _get_story_word_matrix_cursor( $db, $stories_ids, $sentence_separator );

    my $word_matrix = {};
    while ( my $stories = $db->query( "fetch 100 from $story_text_cursor" )->hashes )
    {
        last unless ( @{ $stories } );

        for my $story ( @{ $stories } )
        {
            my $wc = MediaWords::Solr::WordCounts->new();

            # Remove stopwords from the stems
            $wc->include_stopwords( 0 );

            my $sentences_and_story_languages = [];
            for my $sentence ( split( $sentence_separator, $story->{ story_text } ) )
            {
                push(
                    @{ $sentences_and_story_languages },
                    {
                        'story_language' => $story->{ language },
                        'sentence'       => $sentence,
                    }
                );
            }

            my $stem_counts = $wc->count_stems( $sentences_and_story_languages );

            my $stem_count_list = [];
            while ( my ( $stem, $data ) = each( %{ $stem_counts } ) )
            {
                push( @{ $stem_count_list }, [ $stem, $data->{ count }, $data->{ terms } ] );
            }

            if ( $max_words )
            {
                $stem_count_list = [ sort { $b->[ 1 ] <=> $a->[ 1 ] } @{ $stem_count_list } ];
                splice( @{ $stem_count_list }, 0, $max_words );
            }

            $word_matrix->{ $story->{ stories_id } } //= {};
            my $stem_vector = $word_matrix->{ $story->{ stories_id } };
            for my $stem_count ( @{ $stem_count_list } )
            {
                my ( $stem, $count, $terms ) = @{ $stem_count };

                $word_index_lookup->{ $stem } //= $word_index_sequence++;
                my $index = $word_index_lookup->{ $stem };

                $stem_vector->{ $index } += $count;

                map { $word_term_counts->{ $stem }->{ $_ } += $terms->{ $_ } } keys( %{ $terms } );
            }
        }
    }

    $db->commit if ( $use_transaction );

    my $word_list = [];
    for my $stem ( keys( %{ $word_index_lookup } ) )
    {
        my $term_pairs = [];
        while ( my ( $term, $count ) = each( %{ $word_term_counts->{ $stem } } ) )
        {
            push( @{ $term_pairs }, [ $term, $count ] );
        }

        $term_pairs = [ sort { $b->[ 1 ] <=> $a->[ 1 ] } @{ $term_pairs } ];
        $word_list->[ $word_index_lookup->{ $stem } ] = [ $stem, $term_pairs->[ 0 ]->[ 0 ] ];
    }

    return ( $word_matrix, $word_list );
}

1;
