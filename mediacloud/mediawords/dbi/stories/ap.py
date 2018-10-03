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

import hashlib
import re
from typing import List, Pattern, Optional

from mediawords.db import DatabaseHandler
from mediawords.languages.factory import LanguageFactory
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

# All AP stories are expected to be written in English
__AP_LANGUAGE_CODE = 'en'


def get_ap_medium_name() -> str:
    return 'Associated Press - Full Feed'


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


def _get_sentences_from_content(story_text: str) -> List[str]:
    """Given raw HML content, extract the content and parse it into sentences."""
    story_text = decode_object_from_bytes_if_needed(story_text)

    lang = LanguageFactory.language_for_code(__AP_LANGUAGE_CODE)
    sentences = lang.split_text_to_sentences(text=story_text)

    return sentences


def _get_ap_dup_sentence_lengths(db: DatabaseHandler, story_text: str) -> List[int]:
    story_text = decode_object_from_bytes_if_needed(story_text)

    ap_media_id = _get_ap_media_id(db=db)

    if ap_media_id is None:
        return []

    sentences = _get_sentences_from_content(story_text=story_text)

    md5s = []
    for sentence in sentences:
        md5_hash = hashlib.md5(sentence.encode('utf-8')).hexdigest()
        md5s.append(md5_hash)

    sentence_lengths = db.query("""
        SELECT length(sentence) AS len
        FROM story_sentences
        WHERE media_id = %(ap_media_id)s

          -- FIXME this probably never worked because the index is half_md5(), not md5()
          AND md5(sentence) = ANY(%(md5s)s)
    """, {
        'ap_media_id': ap_media_id,
        'md5s': md5s,
    }).flat()

    # MC_REWRITE_TO_PYTHON: Perlism
    if sentence_lengths is None:
        sentence_lengths = []

    return sentence_lengths


def _get_content_pattern_matches(story_text: str,
                                 pattern: Pattern[str],
                                 restrict_to_first: int = 0) -> int:
    story_text = decode_object_from_bytes_if_needed(story_text)
    if isinstance(restrict_to_first, bytes):
        restrict_to_first = decode_object_from_bytes_if_needed(restrict_to_first)
    restrict_to_first = bool(int(restrict_to_first))

    if restrict_to_first:
        story_text = story_text[0:int(len(story_text) * restrict_to_first)]

    matches = re.findall(pattern=pattern, string=story_text)

    return len(matches)


def _get_all_string_match_positions(haystack: str, needle: str) -> List[int]:
    haystack = decode_object_from_bytes_if_needed(haystack)
    needle = decode_object_from_bytes_if_needed(needle)

    positions = []

    for match in re.finditer(pattern=needle, string=haystack):
        positions.append(match.start())

    return positions


def _get_associated_press_near_title(story_title: str, story_text: str) -> bool:
    story_title = decode_object_from_bytes_if_needed(story_title)
    story_text = decode_object_from_bytes_if_needed(story_text)

    story_title = story_title.lower()
    story_text = story_text.lower()

    content = re.sub(pattern=r'\s+', repl=' ', string=story_text, flags=re.MULTILINE)

    title_positions = _get_all_string_match_positions(haystack=content, needle=story_title)
    ap_positions = _get_all_string_match_positions(haystack=content, needle='associated press')

    for title_p in title_positions:
        for ap_p in ap_positions:
            if abs(title_p - ap_p) < 256:
                return True

    return False


def _get_dup_sentences_32(db: DatabaseHandler, story_text: str) -> int:
    """Return the number of sentences in the story that are least 32 characters long and are a duplicate of a sentence
    in the associated press media source."""
    story_text = decode_object_from_bytes_if_needed(story_text)

    sentence_lengths = _get_ap_dup_sentence_lengths(db=db, story_text=story_text)

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


def is_syndicated(db: DatabaseHandler,
                  story_text: str,
                  story_title: str = '',
                  story_language: str = '') -> bool:
    """Return True if the stories is syndicated by the Associated Press, False otherwise.

    Uses the decision tree at the top of the module.
    """

    story_title = decode_object_from_bytes_if_needed(story_title)
    story_text = decode_object_from_bytes_if_needed(story_text)
    story_language = decode_object_from_bytes_if_needed(story_language)

    # If the language code is unset, we're assuming that the story is in English
    if not story_language:
        story_language = __AP_LANGUAGE_CODE

    if not story_text:
        log.warning("Story text is unset.")
        return False

    if story_language != __AP_LANGUAGE_CODE:
        log.debug("Story is not in English.")
        return False

    ap_mentions_sentences = _get_content_pattern_matches(
        story_text=story_text,
        pattern=re.compile(pattern=r'\(ap\)', flags=re.IGNORECASE),
    )
    if ap_mentions_sentences:
        log.debug('ap: ap_mentions_sentences')
        return True

    associated_press_mentions = _get_content_pattern_matches(
        story_text=story_text,
        pattern=re.compile(pattern='associated press', flags=re.IGNORECASE),
    )
    if associated_press_mentions:

        quoted_associated_press_mentions = _get_content_pattern_matches(
            story_text=story_text,
            pattern=re.compile(pattern=r'["\'\|].{0,8}associated press.{0,8}["\'\|]', flags=re.IGNORECASE),
        )
        if quoted_associated_press_mentions:
            log.debug('ap: quoted_associated_press')
            return True

        dup_sentences_32 = _get_dup_sentences_32(db=db, story_text=story_text)
        if dup_sentences_32 == 1:
            log.debug('ap: assoc press -> dup_sentences_32')
            return True

        elif dup_sentences_32 == 0:

            associated_press_near_title = _get_associated_press_near_title(
                story_title=story_title,
                story_text=story_text,
            )
            if associated_press_near_title:
                log.debug('ap: assoc press -> near title')
                return True

            ap_news_mentions = _get_content_pattern_matches(
                story_text=story_text,
                pattern=re.compile('ap news', flags=re.IGNORECASE),
            )
            if ap_news_mentions:
                log.debug('ap: assoc press -> ap news')
                return True

            else:
                log.debug('ap: assoc press -> no ap news')
                return False

        else:  # dup_sentences_32 == 2
            associated_press_near_title = _get_associated_press_near_title(
                story_title=story_title,
                story_text=story_text,
            )

            if associated_press_near_title:
                log.debug('ap: assoc press near title')
                return True

            else:

                associated_press_tag_mentions = _get_content_pattern_matches(
                    story_text=story_text,
                    pattern=re.compile(pattern='<[^<>]*associated press[^<>]*>', flags=re.IGNORECASE)
                )

                if associated_press_tag_mentions:
                    log.debug('ap: assoc press title -> tag')
                    return False

                else:
                    log.debug('ap: assoc press title -> no tag')
                    return True

    else:

        dup_sentences_32 = _get_dup_sentences_32(db=db, story_text=story_text)

        if dup_sentences_32 == 1:
            ap_mentions_uppercase_location = _get_content_pattern_matches(
                story_text=story_text,
                pattern=re.compile(pattern=r'[A-Z]+\s*\(AP\)'),  # do not ignore case
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
