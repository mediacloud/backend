"""
Routines for determining whether a given story is syndicated from the Associated Press.

The algorithm used in this module was developed using a decision tree algorithm:

    'ap_mentions_sentences',
      '1' => '1', X
      '0' => [ X
             'associated_press_mentions',
               '1' => [ X
                      'quoted_associated_press_first_quarter_mentions',
                        '1' => '1', X
                        '0' => [ X
                               'dup_sentences_32',
                                 '1' => '1', X
                                 '0' => [ X
                                        'associated_press_near_title',
                                          '1' => '1', X
                                          '0' => [ X
                                                 'ap_news_mentions',
                                                   '1' => '1', X
                                                   '0' => [ X
                                                          'ap_mentions',
                                                            '1' => '1', X
                                                            '0' => '0' X
                                 '2' => [ X
                                          'associated_press_near_title', X
                                            '1' => '1', X
                                            '0' => [ X
                                                   'associated_press_tag_mentions', X
                                                     '1' => '0', X
                                                     '0' => '1' X
               '0' => [
                      'dup_sentences_32',
                        '1' => [
                                 'ap_mentions',
                                   '1' => [
                                          'ap_mentions_uppercase_location',
                                            '1' => '1',
                                            '0' => '0'
                                   '0' => '0'
                        '0' => '0',
                        '2' => '1'
"""

import copy
import hashlib
import re
from typing import List, Pattern, Optional

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads import extract_content, fetch_content
from mediawords.dbi.stories.extract import get_text
from mediawords.languages.factory import LanguageFactory
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McIsSyndicatedException(Exception):
    """is_syndicated() exception."""
    pass


def get_ap_medium_name() -> str:
    return 'Associated Press - Full Feed'


def _get_story_content(db: DatabaseHandler, story: dict) -> str:
    story = decode_object_from_bytes_if_needed(story)

    if story.get('content', None):
        return story['content']

    download = story.get('download', None)
    if not download:
        download = db.query("""
            SELECT *
            FROM downloads
            WHERE stories_id = %(stories_id)s
            ORDER BY downloads_id
            LIMIT 1
        """, {'stories_id': story['stories_id']}).hash()

    # There might be no download at all for full text RSS story
    if not download:
        return ''

    if download['state'] != 'success':
        return ''

    try:
        content = fetch_content(db=db, download=download)
    except Exception as ex:
        log.warning("Error fetching content: {}".format(ex))
        return ''

    if content is None:
        log.warning("Fetched content is undefined.")
        return ''

    return content


def _get_ap_media_id(db: DatabaseHandler) -> Optional[int]:
    ap_media = db.query("""
        SELECT media_id
        FROM media
        WHERE name = %(medium_name)s
    """, {'medium_name': get_ap_medium_name()}).flat()

    # MC_REWRITE_TO_PYTHON: Perlism
    if ap_media is None:
        ap_media = []

    if len(ap_media) > 0:
        return ap_media[0]

    else:
        return None


def _get_ap_dup_sentence_lengths_from_db(db: DatabaseHandler, story: dict) -> List[int]:
    story = decode_object_from_bytes_if_needed(story)

    ap_media_id = _get_ap_media_id(db=db)
    if ap_media_id is None:
        return []

    sentences = db.query("""

        WITH sentence_md5s AS (
            SELECT md5(ss.sentence) AS md5_sentence
            FROM story_sentences AS ss
            WHERE ss.stories_id = %(stories_id)s
              AND ss.media_id != %(ap_media_id)s
        )
        SELECT *
        FROM story_sentences
        WHERE media_id = %(ap_media_id)s

          -- FIXME this probably doesn't work because the index is half_md5(), not md5()
          AND md5(sentence) IN (
              SELECT md5_sentence
              FROM sentence_md5s
          )

    """, {
        'stories_id': story['stories_id'],
        'ap_media_id': ap_media_id,
    }).hashes()

    # MC_REWRITE_TO_PYTHON: Perlism
    if sentences is None:
        sentences = []

    sentence_lengths = []
    for sentence in sentences:
        sentence_lengths.append(len(sentence['sentence']))

    return sentence_lengths


def _get_sentences_from_content(story: dict) -> List[str]:
    """Given raw HML content, extract the content and parse it into sentences."""
    story = decode_object_from_bytes_if_needed(story)

    content = story['content']

    text = extract_content(content=content)['extracted_text']

    lang = LanguageFactory.language_for_code(story.get('language', ''))
    if not lang:
        lang = LanguageFactory.default_language()

    sentences = lang.split_text_to_sentences(text=text)

    return sentences


def _get_ap_dup_sentence_lengths_from_content(db: DatabaseHandler, story: dict) -> List[int]:
    story = decode_object_from_bytes_if_needed(story)

    ap_media_id = _get_ap_media_id(db=db)

    if ap_media_id is None:
        return []

    sentences = _get_sentences_from_content(story=story)

    md5s = []
    for sentence in sentences:
        md5_hash = hashlib.md5(sentence.encode('utf-8')).hexdigest()
        md5s.append(md5_hash)

    sentence_lengths = db.query("""
        SELECT length(sentence) AS len
        FROM story_sentences
        WHERE media_id = %(ap_media_id)s

          -- FIXME this probably doesn't work because the index is half_md5(), not md5()
          AND md5(sentence) = ANY(%(md5s)s)
    """, {
        'ap_media_id': ap_media_id,
        'md5s': md5s,
    }).flat()

    # MC_REWRITE_TO_PYTHON: Perlism
    if sentence_lengths is None:
        sentence_lengths = []

    return sentence_lengths


def _get_ap_dup_sentence_lengths(db: DatabaseHandler, story: dict) -> List[int]:
    story = decode_object_from_bytes_if_needed(story)

    if story.get('stories_id', None):
        return _get_ap_dup_sentence_lengths_from_db(db=db, story=story)

    return _get_ap_dup_sentence_lengths_from_content(db=db, story=story)


def _get_content_pattern_matches(db: DatabaseHandler,
                                 story: dict,
                                 pattern: Pattern[str],
                                 restrict_to_first: int = 0) -> int:
    story = decode_object_from_bytes_if_needed(story)
    if isinstance(restrict_to_first, bytes):
        restrict_to_first = decode_object_from_bytes_if_needed(restrict_to_first)
    restrict_to_first = bool(int(restrict_to_first))

    content = _get_story_content(db=db, story=story)

    if restrict_to_first:
        content = content[0:int(len(content) * restrict_to_first)]

    matches = re.findall(pattern=pattern, string=content)

    return len(matches)


def _get_text_pattern_matches(db: DatabaseHandler, story: dict, pattern: Pattern[str]) -> int:
    story = decode_object_from_bytes_if_needed(story)

    text = get_text(db=db, story=story)

    matches = re.findall(pattern=pattern, string=text)

    return len(matches)


def _get_sentence_pattern_matches(db: DatabaseHandler, story: dict, pattern: Pattern[str]) -> int:
    story = decode_object_from_bytes_if_needed(story)

    if story.get('stories_id', None):
        sentences = db.query("""
            SELECT sentence
            FROM story_sentences
            WHERE stories_id = %(stories_id)s
        """, {'stories_id': story['stories_id']}).flat()

        # MC_REWRITE_TO_PYTHON: Perlism
        if sentences is None:
            sentences = []

    else:
        sentences = story.get('sentences', [])

    text = ' '.join(sentences)

    matches = re.findall(pattern=pattern, string=text)

    return len(matches)


def _get_all_string_match_positions(haystack: str, needle: str) -> List[int]:
    haystack = decode_object_from_bytes_if_needed(haystack)
    needle = decode_object_from_bytes_if_needed(needle)

    positions = []

    for match in re.finditer(pattern=needle, string=haystack):
        positions.append(match.start())

    return positions


def _get_associated_press_near_title(db: DatabaseHandler, story: dict) -> bool:
    story = decode_object_from_bytes_if_needed(story)

    content = _get_story_content(db=db, story=story).lower()

    content = re.sub(pattern='\s+', repl=' ', string=content, flags=re.MULTILINE)

    title_positions = _get_all_string_match_positions(haystack=content, needle=story['title'].lower())
    ap_positions = _get_all_string_match_positions(haystack=content, needle='associated press')

    for title_p in title_positions:
        for ap_p in ap_positions:
            if abs(title_p - ap_p) < 256:
                return True

    return False


def _get_dup_sentences_32(db: DatabaseHandler, story: dict) -> int:
    """Return the number of sentences in the story that are least 32 characters long and are a duplicate of a sentence
    in the associated press media source."""
    story = decode_object_from_bytes_if_needed(story)

    sentence_lengths = _get_ap_dup_sentence_lengths(db=db, story=story)

    num_sentences = 0
    for sentence_length in sentence_lengths:
        if sentence_length >= 32:
            num_sentences += 1

    if not num_sentences:
        return 0
    elif num_sentences > 10:
        return 2
    else:
        return 1


def is_syndicated(db: DatabaseHandler, story: dict) -> bool:
    """Return True if the stories is syndicated by the Associated Press, False otherwise.

    Uses the decision tree at the top of the module.
    """
    story = decode_object_from_bytes_if_needed(story)

    if not story:
        raise McIsSyndicatedException("Story is not set.")

    if not story.get('stories_id', None) and story.get('content', None) is None and story.get('language', None) is None:
        raise McIsSyndicatedException(
            '{} object must have a title field and either a stories_id field or a content and a language field.'.format(
                story
            ))

    # Copy story so that we can cache data in the object with introducing side effects
    story = copy.deepcopy(story)

    # Add a sentences field if this is an external story. Do this here so that we don't have to do it repeatedly below
    if not story.get('stories_id', None):
        story['sentences'] = _get_sentences_from_content(story=story)

    ap_mentions_sentences = _get_sentence_pattern_matches(
        db=db,
        story=story,
        pattern=re.compile(pattern='\(ap\)', flags=re.IGNORECASE),
    )
    if ap_mentions_sentences:
        log.debug('ap: ap_mentions_sentences')
        return True

    associated_press_mentions = _get_content_pattern_matches(
        db=db,
        story=story,
        pattern=re.compile(pattern='associated press', flags=re.IGNORECASE),
    )
    if associated_press_mentions:

        quoted_associated_press_mentions = _get_content_pattern_matches(
            db=db,
            story=story,
            pattern=re.compile(pattern='["\'\|].{0,8}associated press.{0,8}["\'\|]', flags=re.IGNORECASE),
        )
        if quoted_associated_press_mentions:
            log.debug('ap: quoted_associated_press')
            return True

        dup_sentences_32 = _get_dup_sentences_32(db=db, story=story)
        if dup_sentences_32 == 1:
            log.debug('ap: assoc press -> dup_sentences_32')
            return True

        elif dup_sentences_32 == 0:

            associated_press_near_title = _get_associated_press_near_title(db=db, story=story)
            if associated_press_near_title:
                log.debug('ap: assoc press -> near title')
                return True

            ap_news_mentions = _get_content_pattern_matches(
                db=db,
                story=story,
                pattern=re.compile('ap news', flags=re.IGNORECASE),
            )
            if ap_news_mentions:
                log.debug('ap: assoc press -> ap news')
                return True

            else:
                log.debug('ap: assoc press -> no ap news')
                return False

        else:  # dup_sentences_32 == 2
            associated_press_near_title = _get_associated_press_near_title(db=db, story=story)

            if associated_press_near_title:
                log.debug('ap: assoc press near title')
                return True

            else:

                associated_press_tag_mentions = _get_content_pattern_matches(
                    db=db,
                    story=story,
                    pattern=re.compile(pattern='<[^<>]*associated press[^<>]*>', flags=re.IGNORECASE)
                )

                if associated_press_tag_mentions:
                    log.debug('ap: assoc press title -> tag')
                    return False

                else:
                    log.debug('ap: assoc press title -> no tag')
                    return True

    else:

        dup_sentences_32 = _get_dup_sentences_32(db=db, story=story)

        if dup_sentences_32 == 1:
            ap_mentions_uppercase_location = _get_text_pattern_matches(
                db=db,
                story=story,
                pattern=re.compile(pattern='[A-Z]+\s*\(AP\)'),  # do not ignore case
            )
            if ap_mentions_uppercase_location:
                log.debug('ap: single dup sentence -> ap upper')
                return True
            else:
                log.debug('ap: single dup sentence -> no upper')
                return False

        elif dup_sentences_32 == 0:
            log.debug('ap: no features')
            return False

        else:
            log.debug('ap: dup sentences > 10')
            return True
