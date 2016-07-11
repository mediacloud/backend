package MediaWords::StoryVectors;

# methods to generate the story_sentences and associated aggregated tables

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Languages::Language;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::AP;
use MediaWords::Util::HTML;
use MediaWords::Util::IdentifyLanguage;
use MediaWords::Util::SQL;
use MediaWords::Util::CoreNLP;

use Data::Dumper;
use Readonly;

# Given a list of text sentences, return a list of story_sentences hashrefs
# with properly escaped values for insertion into the database
sub _get_db_escaped_story_sentence_refs
{
    my ( $db, $story, $sentences ) = @_;

    my $sentence_refs = [];
    for ( my $sentence_num = 0 ; $sentence_num < @{ $sentences } ; $sentence_num++ )
    {
        my $sentence = $sentences->[ $sentence_num ];

        # Identify the language of each of the sentences
        my $sentence_lang = MediaWords::Util::IdentifyLanguage::language_code_for_text( $sentence );
        if ( ( $sentence_lang || '' ) ne ( $story->{ language } || '' ) )
        {
            # Mark the language as unknown if the results for the sentence are not reliable
            unless ( MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( $sentence ) )
            {
                $sentence_lang = '';
            }
        }

        my $sentence_ref = {};
        $sentence_ref->{ sentence }         = $db->quote_varchar( $sentence );
        $sentence_ref->{ language }         = $db->quote_varchar( $sentence_lang );
        $sentence_ref->{ sentence_number }  = $sentence_num;
        $sentence_ref->{ stories_id }       = $story->{ stories_id };
        $sentence_ref->{ media_id }         = $story->{ media_id };
        $sentence_ref->{ publish_date }     = $db->quote_timestamp( $story->{ publish_date } );
        $sentence_ref->{ disable_triggers } = $db->quote_bool( MediaWords::DB::story_triggers_disabled() );

        push( @{ $sentence_refs }, $sentence_ref );
    }

    return $sentence_refs;
}

# Get unique sentences from the list, maintaining the original order
sub _get_unique_sentences_in_story
{
    my ( $sentences ) = @_;

    my $unique_sentences       = [];
    my $unique_sentence_lookup = {};
    for my $sentence ( @{ $sentences } )
    {
        unless ( $unique_sentence_lookup->{ $sentence } )
        {
            $unique_sentence_lookup->{ $sentence } = 1;
            push( @{ $unique_sentences }, $sentence );
        }
    }

    return $unique_sentences;
}

# Insert the story sentences into the DB, optionally skipping duplicate
# sentences by setting is_dup = 't' to the found duplicates that are already in
# the table. Returns arrayref of sentences that were inserted into the table.
sub _insert_story_sentences($$$;$)
{
    my ( $db, $story, $sentences, $no_dedup_sentences ) = @_;

    my $stories_id = $story->{ stories_id };
    my $media_id   = $story->{ media_id };

    # Story's publish date is the same for all the sentences, so we might as
    # well pass it as a constant
    my $escaped_story_publish_date = $db->quote_date( $story->{ publish_date } );

    unless ( scalar( @{ $sentences } ) )
    {
        WARN( "Story sentences are empty for story $stories_id" );
        return;
    }

    my $dedup_sentences_statement;
    if ( $no_dedup_sentences )
    {
        DEBUG( "Won't de-duplicate sentences for story $stories_id because 'no_dedup_sentences' is set." );

        $dedup_sentences_statement = <<SQL;
            -- Nothing to deduplicate, return empty list
            SELECT NULL
            WHERE 1 = 0
SQL
    }
    else
    {
        # Limit to unique sentences within a story
        $sentences = _get_unique_sentences_in_story( $sentences );

        # Set is_dup = 't' to sentences already in the table, return those to
        # be later skipped on INSERT of new sentences
        $dedup_sentences_statement = <<"SQL";
            UPDATE story_sentences
            SET is_dup = 't',
                disable_triggers = 't'
            FROM new_sentences
            WHERE half_md5(story_sentences.sentence) = half_md5(new_sentences.sentence)
              AND week_start_date( story_sentences.publish_date::date )
                  = week_start_date( $escaped_story_publish_date )
              AND story_sentences.media_id = new_sentences.media_id
            RETURNING story_sentences.sentence
SQL
    }

    # Convert to list of hashrefs (values escaped for insertion into database)
    my $sentence_refs = _get_db_escaped_story_sentence_refs( $db, $story, $sentences );

    # Ordered list of columns
    my @story_sentences_columns = sort( keys( %{ $sentence_refs->[ 0 ] } ) );
    my $str_story_sentences_columns = join( ', ', @story_sentences_columns );

    # List of sentences (in predefined column order)
    my @new_sentences_sql;
    foreach my $sentence_ref ( @{ $sentence_refs } )
    {
        my @new_sentence_sql;
        foreach my $column ( @story_sentences_columns )
        {
            push( @new_sentence_sql, $sentence_ref->{ $column } );
        }
        push( @new_sentences_sql, '(' . join( ', ', @new_sentence_sql ) . ')' );
    }
    my $str_new_sentences_sql = "\n" . join( ",\n", @new_sentences_sql );

    my $sql = <<"SQL";
        WITH new_sentences ($str_story_sentences_columns) AS (VALUES
            -- New sentences to potentially insert
            $str_new_sentences_sql
        ),
        duplicate_sentences AS (
            -- Either a list of duplicate sentences already found in the table
            -- or an empty list if deduplication is disabled
            $dedup_sentences_statement
        )
        INSERT INTO story_sentences ($str_story_sentences_columns)
        SELECT $str_story_sentences_columns
        FROM new_sentences
        WHERE sentence NOT IN (
            -- Skip the ones for which we've just set is_dup = 't'
            SELECT sentence
            FROM duplicate_sentences
        )
        RETURNING story_sentences.sentence
SQL

    DEBUG "Adding advisory lock on media ID $media_id...";
    $db->query(
        <<EOF,
        SELECT pg_advisory_lock(?)
EOF
        $media_id
    );

    DEBUG "Running sentence insertion + deduplication query:\n$sql";

    # Insert sentences
    my $inserted_sentences = $db->query( $sql )->flat();

    DEBUG "Removing advisory lock on media ID $media_id...";
    $db->query(
        <<EOF,
        SELECT pg_advisory_unlock(?)
EOF
        $media_id
    );

    return $inserted_sentences;
}

sub _get_sentences_from_story_text
{
    my ( $story_text, $story_lang ) = @_;

    # Tokenize into sentences
    my $lang = MediaWords::Languages::Language::language_for_code( $story_lang );
    if ( !$lang )
    {
        $lang = MediaWords::Languages::Language::default_language();
    }

    my $sentences = $lang->get_sentences( $story_text );

    return $sentences;
}

# Apply manual filters to clean out sentences that we think are junk
sub _clean_sentences
{
    my ( $sentences ) = @_;

    my @cleaned_sentences;

    for my $sentence ( @{ $sentences } )
    {
        unless ( $sentence =~ /(\[.*\{){5,}/ )
        {
            # Drop sentences that are all ascii and 5 characters or less (keep
            # non-ASCII because those are sometimes logograms)
            unless ( $sentence =~ /^[[:ascii:]]{0,5}$/ )
            {
                push( @cleaned_sentences, $sentence );
            }
        }
    }

    return \@cleaned_sentences;
}

# detect whether the story is syndicated and update stories.ap_syndicated
sub _update_ap_syndicated
{
    my ( $db, $story ) = @_;

    return unless ( $story->{ language } && $story->{ language } eq 'en' );

    my $ap_syndicated = MediaWords::DBI::Stories::AP::is_syndicated( $db, $story );

    $db->query( "delete from stories_ap_syndicated where stories_id = \$1", $story->{ stories_id } );

    $db->query( <<SQL, $story->{ stories_id }, $ap_syndicated );
insert into stories_ap_syndicated ( stories_id, ap_syndicated ) values ( \$1, \$2 )
SQL

    $story->{ ap_syndicated } = $ap_syndicated;
}

# update story vectors for the given story, updating story_sentences
# if no_delete() is true, do not try to delete existing entries in the above table before creating new ones
# (useful for optimization if you are very sure no story vectors exist for this story).  If
# $extractor_args->no_dedup_sentences() is true, do not perform sentence deduplication (useful if you are
# reprocessing a small set of stories)
sub update_story_sentences_and_language($$;$)
{
    my ( $db, $story, $extractor_args ) = @_;

    $extractor_args //= MediaWords::DBI::Stories::ExtractorArguments->new();

    my $stories_id = $story->{ stories_id };

    unless ( $extractor_args->no_delete() )
    {
        $db->query( 'DELETE FROM story_sentences WHERE stories_id = ?', $stories_id );
    }

    my $story_text = $story->{ story_text } || MediaWords::DBI::Stories::get_text_for_word_counts( $db, $story ) || '';

    my $story_lang = MediaWords::Util::IdentifyLanguage::language_code_for_text( $story_text, '' );

    my $sentences = _get_sentences_from_story_text( $story_text, $story_lang );

    if ( !$story->{ language } || ( $story_lang ne $story->{ language } ) )
    {
        $db->query( "UPDATE stories SET language = ? WHERE stories_id = ?", $story_lang, $stories_id );
        $story->{ language } = $story_lang;
    }

    die "Sentences for story $stories_id are undefined." unless ( defined $sentences );

    unless ( scalar @{ $sentences } )
    {
        DEBUG( sub { "Story $stories_id doesn't have any sentences." } );
        return;
    }

    $sentences = _clean_sentences( $sentences );

    _insert_story_sentences( $db, $story, $sentences, $extractor_args->no_dedup_sentences() );

    _update_ap_syndicated( $db, $story );

    # FIXME remove commit here because transaction wasn't started in this subroutine
    $db->dbh->{ AutoCommit } || $db->commit;

    unless ( $extractor_args->skip_corenlp_annotation() )
    {
        if (    MediaWords::Util::CoreNLP::annotator_is_enabled()
            and MediaWords::Util::CoreNLP::story_is_annotatable( $db, $stories_id ) )
        {
            # Add to CoreNLP job queue
            DEBUG "Adding story $stories_id to CoreNLP annotation queue...";
            MediaWords::Job::AnnotateWithCoreNLP->add_to_queue( { stories_id => $stories_id } );
        }
        else
        {
            DEBUG "Won't add $stories_id to CoreNLP annotation queue because it's not annotatable with CoreNLP";
        }
    }
    else
    {
        DEBUG "Won't add $stories_id to CoreNLP annotation queue because it's set be skipped";
    }
}

1;
