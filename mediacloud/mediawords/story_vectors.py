import re
from typing import List, Dict

from mediawords.db import DatabaseHandler
from mediawords.dbi.stories.ap import is_syndicated
from mediawords.dbi.stories.extract import get_text_for_word_counts
from mediawords.dbi.stories.extractor_arguments import ExtractorArguments
from mediawords.languages.factory import LanguageFactory
from mediawords.util.identify_language import language_code_for_text, identification_would_be_reliable
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McMediumIsLockedException(Exception):
    """medium_is_locked() exception.

    If thrown, doesn't mean that medium is (un)locked, just that an error has occurred while testing if it is."""
    pass


class McUpdateStorySentencesAndLanguageException(Exception):
    """update_story_sentences_and_language() exception."""
    pass


def medium_is_locked(db: DatabaseHandler, media_id: int) -> bool:
    """Use a new blocking check to see if the given media_id is locked by a postgres advisory lock (used within
    _insert_story_sentences below). Return True if it is locked, False otherwise."""

    if isinstance(media_id, bytes):
        media_id = decode_object_from_bytes_if_needed(media_id)
    media_id = int(media_id)

    got_lock = db.query("SELECT pg_try_advisory_lock(%(media_id)s)", {'media_id': media_id}).flat()[0]
    if got_lock:
        db.query("SELECT pg_advisory_unlock(%(media_id)s)", {'media_id': media_id})

    return not got_lock


def _get_db_escaped_story_sentence_dicts(
        db: DatabaseHandler,
        story: dict,
        sentences: List[str],
) -> List[Dict[str, str]]:
    """Given a list of text sentences, return a list of sentences with properly escaped values for insertion."""
    story = decode_object_from_bytes_if_needed(story)
    sentences = decode_object_from_bytes_if_needed(sentences)

    sentence_dicts = []

    sentence_num = 0
    for sentence in sentences:

        # Identify the language of each of the sentences
        sentence_lang = language_code_for_text(sentence)
        if (sentence_lang or '') != (story['language'] or ''):
            # Mark the language as unknown if the results for the sentence are not reliable
            if not identification_would_be_reliable(text=sentence):
                sentence_lang = ''

        sentence_dicts.append({
            'sentence': db.quote_varchar(sentence),
            'language': db.quote_varchar(sentence_lang),
            'sentence_number': str(sentence_num),
            'stories_id': str(story['stories_id']),
            'media_id': str(story['media_id']),
            'publish_date': db.quote_timestamp(story['publish_date']),
        })

        sentence_num += 1

    return sentence_dicts


def _get_unique_sentences_in_story(sentences: List[str]) -> List[str]:
    """Get unique sentences from the list, maintaining the original order."""
    sentences = decode_object_from_bytes_if_needed(sentences)

    unique_sentences = []
    unique_sentence_lookup = set()

    for sentence in sentences:
        if sentence not in unique_sentence_lookup:
            unique_sentence_lookup.add(sentence)
            unique_sentences.append(sentence)

    return unique_sentences


def _insert_story_sentences(
        db: DatabaseHandler,
        story: dict,
        sentences: List[str],
        no_dedup_sentences: bool = False,
) -> List[str]:
    """Insert the story sentences into story_sentences, optionally skipping duplicate sentences by setting is_dup = 't'
    to the found duplicates that are already in the table.

    Returns list of sentences that were inserted into the table.
    """

    story = decode_object_from_bytes_if_needed(story)
    sentences = decode_object_from_bytes_if_needed(sentences)
    if isinstance(no_dedup_sentences, bytes):
        no_dedup_sentences = decode_object_from_bytes_if_needed(no_dedup_sentences)
    no_dedup_sentences = bool(int(no_dedup_sentences))

    stories_id = story['stories_id']
    media_id = story['media_id']

    # Story's publish date is the same for all the sentences, so we might as well pass it as a constant
    escaped_story_publish_date = db.quote_date(story['publish_date'])

    if len(sentences) == 0:
        log.warning("Story sentences are empty for story {}.".format(stories_id))
        return []

    if no_dedup_sentences:
        log.debug("Won't de-duplicate sentences for story {} because 'no_dedup_sentences' is set.".format(stories_id))

        dedup_sentences_statement = """

            -- Nothing to deduplicate, return empty list
            SELECT NULL
            WHERE 1 = 0

        """

    else:

        # Limit to unique sentences within a story
        sentences = _get_unique_sentences_in_story(sentences)

        # Set is_dup = 't' to sentences already in the table, return those to be later skipped on INSERT of new
        # sentences
        dedup_sentences_statement = """

            -- noinspection SqlResolve
            UPDATE story_sentences
            SET is_dup = 't'
            FROM new_sentences
            WHERE half_md5(story_sentences.sentence) = half_md5(new_sentences.sentence)
              AND week_start_date(story_sentences.publish_date::date) = week_start_date({})
              AND story_sentences.media_id = new_sentences.media_id
            RETURNING story_sentences.sentence

        """.format(escaped_story_publish_date)

    # Convert to list of dicts (values escaped for insertion into database)
    sentence_dicts = _get_db_escaped_story_sentence_dicts(db=db, story=story, sentences=sentences)

    # Ordered list of columns
    story_sentences_columns = sorted(sentence_dicts[0].keys())
    str_story_sentences_columns = ', '.join(story_sentences_columns)

    # List of sentences (in predefined column order)
    new_sentences_sql = []
    for sentence_dict in sentence_dicts:
        new_sentence_sql = []
        for column in story_sentences_columns:
            new_sentence_sql.append(sentence_dict[column])
        new_sentences_sql.append('({})'.format(', '.join(new_sentence_sql)))
    str_new_sentences_sql = "\n{}".format(",\n".join(new_sentences_sql))

    sql = """

        -- noinspection SqlType,SqlResolve
        WITH new_sentences ({str_story_sentences_columns}) AS (VALUES
            -- New sentences to potentially insert
            {str_new_sentences_sql}
        ),
        duplicate_sentences AS (
            -- Either a list of duplicate sentences already found in the table or an empty list if deduplication is
            -- disabled
            --
            -- The query assumes that there are no existing sentences for this story in the "story_sentences" table, so
            -- if you are reextracting a story, DELETE its sentences from "story_sentences" before running this query.
            {dedup_sentences_statement}
        )
        INSERT INTO story_sentences ({str_story_sentences_columns})
        SELECT {str_story_sentences_columns}
        FROM new_sentences
        WHERE sentence NOT IN (
            -- Skip the ones for which we've just set is_dup = 't'
            SELECT sentence
            FROM duplicate_sentences
        )
        RETURNING story_sentences.sentence

    """.format(
        str_story_sentences_columns=str_story_sentences_columns,
        str_new_sentences_sql=str_new_sentences_sql,
        dedup_sentences_statement=dedup_sentences_statement,
    )

    log.debug("Adding advisory lock on media ID {}...".format(media_id))
    db.query("SELECT pg_advisory_lock(%(media_id)s)", {'media_id': media_id})

    log.debug("Running sentence insertion + deduplication query:\n{}".format(sql))

    # Insert sentences
    inserted_sentences = db.query(sql).flat()

    log.debug("Removing advisory lock on media ID {}...".format(media_id))
    db.query("SELECT pg_advisory_unlock(%(media_id)s)", {'media_id': media_id})

    db.query("""
        UPDATE media_stats
        SET num_sentences = num_sentences + %(inserted_sentence_count)s
        WHERE media_id = %(media_id)s
          AND stat_date = %(publish_date)s::date
    """, {
        'inserted_sentence_count': len(inserted_sentences),
        'media_id': media_id,
        'publish_date': story['publish_date'],
    })

    return inserted_sentences


def _get_sentences_from_story_text(story_text: str, story_lang: str) -> List[str]:
    """Split story text to individual sentences."""
    story_text = decode_object_from_bytes_if_needed(story_text)
    story_lang = decode_object_from_bytes_if_needed(story_lang)

    # Tokenize into sentences
    lang = LanguageFactory.language_for_code(story_lang)
    if not lang:
        lang = LanguageFactory.default_language()

    sentences = lang.split_text_to_sentences(story_text)

    return sentences


def _clean_sentences(sentences: List[str]) -> List[str]:
    """Apply manual filters to clean out sentences that we think are junk."""
    sentences = decode_object_from_bytes_if_needed(sentences)

    cleaned_sentences = []

    for sentence in sentences:
        if not re.match(pattern="(\[.*\{){5,}", string=sentence):
            # Drop sentences that are all ASCII and 5 characters or less (keep non-ASCII because those are sometimes
            # logograms)
            if not re.match(pattern="^[\x00-\x7F]{0,5}$", string=sentence):
                cleaned_sentences.append(sentence)

    return cleaned_sentences


def _update_ap_syndicated(db: DatabaseHandler, story: dict) -> dict:
    """Detect whether the story is syndicated and update stories.ap_syndicated."""
    # FIXME write a test once AP gets reenabled

    story = decode_object_from_bytes_if_needed(story)

    if story.get('language', '') != 'en':
        return story

    ap_syndicated = is_syndicated(db=db, story=story)

    db.query("""
        DELETE FROM stories_ap_syndicated
        WHERE stories_id = %(stories_id)s
    """, {'stories_id': story['stories_id']})

    db.query("""
        INSERT INTO stories_ap_syndicated (stories_id, ap_syndicated)
        VALUES (%(stories_id)s, %(ap_syndicated)s)
    """, {'stories_id': story['stories_id'], 'ap_syndicated': ap_syndicated})

    story['ap_syndicated'] = ap_syndicated

    return story


def _delete_story_sentences(db: DatabaseHandler, story: dict) -> None:
    """Delete any existing stories for the given story and also update media_stats to adjust for the deletion."""
    story = decode_object_from_bytes_if_needed(story)

    num_deleted = db.query("""
        DELETE FROM story_sentences
        WHERE stories_id = %(stories_id)s
    """, {'stories_id': story['stories_id']}).rows()

    if num_deleted > 0:
        db.query("""
            UPDATE media_stats
            SET num_sentences = num_sentences - %(num_deleted)s
            WHERE media_id = %(media_id)s
              AND stat_date = %(publish_date)s::date
        """, {
            'num_deleted': num_deleted,
            'media_id': story['media_id'],
            'publish_date': story['publish_date'],
        })


def update_story_sentences_and_language(db: DatabaseHandler,
                                        story: dict,
                                        extractor_args: ExtractorArguments = ExtractorArguments()) -> None:
    """Update story vectors for the given story, updating "story_sentences".

    If extractor_args.no_delete() is True, do not try to delete existing entries in the above table before creating new
    ones (useful for optimization if you are very sure no story vectors exist for this story).

    If extractor_args.no_dedup_sentences() is True, do not perform sentence deduplication (useful if you are
    reprocessing a small set of stories).
    """

    story = decode_object_from_bytes_if_needed(story)

    use_transaction = not db.in_transaction()

    if use_transaction:
        db.begin()

    stories_id = story['stories_id']

    if not extractor_args.no_delete():
        _delete_story_sentences(db=db, story=story)

    story_text = story.get('story_text', None)
    if not story_text:
        story_text = get_text_for_word_counts(db=db, story=story)
        if not story_text:
            story_text = ''

    story_lang = language_code_for_text(text=story_text)

    sentences = _get_sentences_from_story_text(story_text=story_text, story_lang=story_lang)

    if (not story.get('language', None)) or story.get('language', None) != story_lang:
        db.query("""
            UPDATE stories
            SET language = %(story_lang)s
            WHERE stories_id = %(stories_id)s
        """, {'stories_id': stories_id, 'story_lang': story_lang})
        story['language'] = story_lang

    if sentences is None:
        raise McUpdateStorySentencesAndLanguageException("Sentences for story {} are undefined.".format(stories_id))

    if len(sentences) == 0:
        log.debug("Story {} doesn't have any sentences.".format(stories_id))
        return

    sentences = _clean_sentences(sentences)

    _insert_story_sentences(
        db=db,
        story=story,
        sentences=sentences,
        no_dedup_sentences=extractor_args.no_dedup_sentences(),
    )

    _update_ap_syndicated(db=db, story=story)

    if use_transaction:
        db.commit()
