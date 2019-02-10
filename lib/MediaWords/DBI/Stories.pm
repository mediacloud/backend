package MediaWords::DBI::Stories;

#
# Various helper functions for stories
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.stories.stories' );

use HTML::Entities;

use MediaWords::Solr::WordCounts;
use MediaWords::Util::ParseHTML;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

# common title prefixes that can be ignored for dup title matching
Readonly my $DUP_TITLE_PREFIXES => [
    qw/opinion analysis report perspective poll watch exclusive editorial reports breaking nyt/,
    qw/subject source wapo sources video study photos cartoon cnn today wsj review timeline/,
    qw/revealed gallup ap read experts op-ed commentary feature letters survey/
];

# Given two lists of hashes, $stories and $story_data, each with
# a stories_id field in each row, assign each key:value pair in
# story_data to the corresponding row in $stories.  If $list_field
# is specified, push each the value associate with key in each matching
# stories_id row in story_data field into a list with the name $list_field
# in stories.
#
# Return amended stories hashref.
sub attach_story_data_to_stories
{
    my ( $stories, $story_data, $list_field ) = @_;

    map { $_->{ $list_field } = [] } @{ $stories } if ( $list_field );

    unless ( scalar @{ $story_data } )
    {
        return $stories;
    }

    TRACE "stories size: " . scalar( @{ $stories } );
    TRACE "story_data size: " . scalar( @{ $story_data } );

    my $story_data_lookup = {};
    for my $sd ( @{ $story_data } )
    {
        my $sd_id = $sd->{ stories_id };
        if ( $list_field )
        {
            $story_data_lookup->{ $sd_id } //= { $list_field => [] };
            push( @{ $story_data_lookup->{ $sd_id }->{ $list_field } }, $sd );
        }
        else
        {
            $story_data_lookup->{ $sd_id } = $sd;
        }
    }

    for my $story ( @{ $stories } )
    {
        my $sid = $story->{ stories_id };
        if ( my $sd = $story_data_lookup->{ $sid } )
        {
            map { $story->{ $_ } = $sd->{ $_ } } keys( %{ $sd } );
            TRACE "story matched: " . Dumper( $story );
        }
    }

    return $stories;
}

# Call attach_story_data_to_stories_ids with a basic query that includes the fields:
# stories_id, title, publish_date, url, guid, media_id, language, media_name.
#
# Return the updated stories arrayref.
sub attach_story_meta_data_to_stories
{
    my ( $db, $stories ) = @_;

    my $use_transaction = !$db->in_transaction();
    $db->begin if ( $use_transaction );

    my $ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ stories_id } ) } @{ $stories } ] );

    my $story_data = $db->query( <<END )->hashes;
select s.stories_id, s.title, s.publish_date, s.url, s.guid, s.media_id, s.language, m.name media_name
    from stories s join media m on ( s.media_id = m.media_id )
    where s.stories_id in ( select id from $ids_table )
END

    $stories = attach_story_data_to_stories( $stories, $story_data );

    $db->commit if ( $use_transaction );

    return $stories;
}

# break a story down into parts separated by [-:|]
sub _get_title_parts
{
    my ( $title ) = @_;

    $title = decode_entities( $title );

    $title = lc( $title );

    $title = MediaWords::Util::ParseHTML::html_strip( $title ) if ( $title =~ /\</ );
    $title = decode_entities( $title );

    my $sep_chars = '\-\:\|';

    # get rid of very common one word prefixes so that opinion: foo bar foo will match report - foo bar foo even if
    # foo bar foo never appears as a solo title
    my $prefix_re = '(?:' . join( '|', @{ $DUP_TITLE_PREFIXES } ) . ')';
    $title =~ s/^(\s*$prefix_re\s*[$sep_chars]\s*)//;

    my $title_parts;
    if ( $title =~ m~https?://[^ ]*~ )
    {
        return [ $title ];
    }
    else
    {
        $title =~ s/(\w)\:/$1 :/g;
        $title_parts = [ split( /\s*[$sep_chars]+\s*/, $title ) ];
    }

    if ( @{ $title_parts } > 1 )
    {
        unshift( @{ $title_parts }, $title );
    }

    map { s/[[:punct:]]//g; s/\s+/ /g; s/^\s+//; s/\s+$//; } @{ $title_parts };

    return $title_parts;
}

# get the difference in seconds between the newest and oldest story in the list
sub _get_story_date_range
{
    my ( $stories ) = @_;

    my $epoch_dates = [ map { MediaWords::Util::SQL::get_epoch_from_sql_date( $_->{ publish_date } ) } @{ $stories } ];

    return List::Util::max( @{ $epoch_dates } ) - List::Util::min( @{ $epoch_dates } );
}

# Get duplicate stories within the set of stories by breaking the title of each story into parts by [-:|] and looking for
# any such part that is the sole title part for any story and is at least 4 words long and is not the title of a story
# with a path-less url.  Any story that includes that title part becames a duplicate.  return a list of duplciate story
# lists. Do not return any list of duplicates with greater than 25 duplicates for fear that the title deduping is
# interacting with some title form in a goofy way.
#
# By default, assume that any solr title part that is less than 5 words long or that is associated with a story whose
# url has no path is a home page and therefore should not be considered as a possible duplicate title part.  If
# $assume_no_home_pages is true, treat every solr url part greater than two words as a potential duplicate title part.
# 
# Don't recognize twitter stories as dups, because the tweet title is the tweet text, and we want to capture retweets.
sub get_medium_dup_stories_by_title
{
    my ( $db, $stories, $assume_no_home_pages ) = @_;

    my $title_part_counts = {};
    for my $story ( @{ $stories } )
    {
        next if ( $story->{ url } && ( $story->{ url } =~ /https?:\/\/(twitter\.com)/i ) );

        my $title_parts = _get_title_parts( $story->{ title } );

        for ( my $i = 0 ; $i < @{ $title_parts } ; $i++ )
        {
            my $title_part = $title_parts->[ $i ];

            if ( $i == 0 )
            {
                my $num_words = scalar( split( / /, $title_part ) );
                my $uri_path = MediaWords::Util::URL::get_url_path_fast( $story->{ url } );

                # solo title parts that are only a few words might just be the media source name
                next if ( ( $num_words < 5 ) && !$assume_no_home_pages );

                # likewise, a solo title of a story with a url with no path is probably the media source name
                next if ( ( $uri_path =~ /^\/?$/ ) && !$assume_no_home_pages );

                $title_part_counts->{ $title_parts->[ 0 ] }->{ solo } = 1;
            }

            # this function needs to work whether or not the story has already been inserted into the db
            my $id = $story->{ stories_id } || $story->{ guid };

            $title_part_counts->{ $title_part }->{ count }++;
            $title_part_counts->{ $title_part }->{ stories }->{ $id } = $story;
        }
    }

    my $duplicate_stories = [];
    for my $t ( grep { $_->{ solo } } values( %{ $title_part_counts } ) )
    {
        my $num_stories = scalar( keys( %{ $t->{ stories } } ) );

        if ( $num_stories > 1 )
        {
            my $dup_stories = [ values( %{ $t->{ stories } } ) ];
            if ( ( $num_stories < 26 ) || ( _get_story_date_range( $dup_stories ) < ( 7 * 86400 ) ) )
            {
                push( @{ $duplicate_stories }, $dup_stories );
            }
            else
            {
                my $dup_title = ( values( %{ $t->{ stories } } ) )[ 0 ]->{ title };

                TRACE "Cowardly refusing to mark $num_stories stories as dups [$dup_title]";
            }
        }
    }

    return $duplicate_stories;
}

# Get duplicate stories within the given set that are duplicates because the normalized url for two given stories is the
# same.  Return a list of story duplicate lists.  Do not return any list of duplicates with greater than 5 duplicates for
# fear that the url normalization is interacting with some url form in a goofy way
sub get_medium_dup_stories_by_url
{
    my ( $db, $stories ) = @_;

    my $url_lookup = {};
    for my $story ( @{ $stories } )
    {
        if ( !$story->{ url } )
        {
            WARN "No URL in story: " . Dumper( $story );
            next;
        }

        my $nu = MediaWords::Util::URL::normalize_url_lossy( $story->{ url } );
        $story->{ normalized_url } = $nu;
        push( @{ $url_lookup->{ $nu } }, $story );
    }

    return [ grep { ( @{ $_ } > 1 ) && ( @{ $_ } < 6 ) } values( %{ $url_lookup } ) ];
}

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
