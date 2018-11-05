import re
import html
from typing import List

import mediawords.util.parse_html
import mediawords.util.sql

from mediawords.util.log import create_logger
log = create_logger(__name__)

# common title prefixes that can be ignored for dup title matching
DUP_TITLE_PREFIXES = (
    "opinion analysis report perspective poll watch exclusive editorial reports breaking nyt "
    "subject source wapo sources video study photos cartoon cnn today wsj review timeline "
    "revealed gallup ap read experts op-ed commentary feature letters survey "
).split()


def _get_title_parts(title: str) -> List[str]:
    """Break a story down into parts separated by [-:|]"""

    title = html.unescape(title).lower()

    if '<' in title:
        title = mediawords.util.parse_html.html_strip(title)

    sep_chars_re = r'[\-\:\|]'

    # get rid of very common one word prefixes so that opinion: foo bar foo will match report - foo bar foo even if
    # foo bar foo never appears as a solo title
    prefix_re = '(?:' + '|'.join(DUP_TITLE_PREFIXES) + ')'
    title = re.sub(r'^\s*' + prefix_re + r'\s*' + sep_chars_re + r'\s*', '', title)

    title_parts = None
    if re.search(r'https?://[^ ]*', title):
        return [title]
    else:
        title = re.sub(sep_chars_re, ':', title)
        title_parts = title.split(':')

    if len(title_parts) > 1:
        title_parts.insert(0, title)

    title_parts = [re.sub(r'[[:punct:]]', '', t) for t in title_parts]
    title_parts = [t.strip()for t in title_parts]

    return title_parts


def _get_story_date_range(stories: List[dict]) -> List[dict]:
    """Get the difference in seconds between the newest and oldest story in the list."""
    epoch_dates = [mediawords.util.sql.get_epoch_from_sql_date(s['publish_date']) for s in stories]

    return max(epoch_dates) - min(epoch_dates)


def get_medium_dup_stories_by_title(stories: List, assume_no_home_pages: bool = False) -> List:
    """
    Get duplicate stories within the stories by breaking the title of each story into parts by [-:|] and looking for
    any such part that is the sole title part for a story and is at least 4 words long and is not the title of a story
    with a pathless url. Any story that includes that title part becames a duplicate.  return a list of duplciate story
    lists. Do not return any list of duplicates with greater than 25 duplicates for fear that the title deduping is
    interacting with some title form in a goofy way.

    By default, assume that any solr title part that is less than 5 words long or that is associated with a story whose
    url has no path is a home page and therefore should not be considered as a possible duplicate title part.  If
    assume_no_home_pages is true, treat every solr url part greater than two words as a potential duplicate title part.

    Don't recognize twitter stories as dups because the tweet title is the tweet text, and we want to capture retweets.

    Arguments:
    * stories - list of stories to check for dups
    * assume_no_home_pages - assume that no stories are home pages (a story detected as a home page cannot be a dup)

    Returns:
    * a list of duplicate story lists
    """
    title_part_counts = {}
    for story in stories:
        if story['url'] and re.match(r'^https?:\/\/twitter\.com', story['url']):
            continue

        title_parts = _get_title_parts(story['title'])
        log.warning(title_parts)

        for i, title_part in enumerate(title_parts):
            if i == 0:
                num_words = len(title_part.split())
                uri_path = mediawords.util.url.get_url_path_fast(story['url'])

                # solo title parts that are only a few words might just be the media source name
                if num_words < 5 and not assume_no_home_pages:
                    continue

                # likewise, a solo title of a story with a url with no path is probably the media source name
                if re.match(r'^\/?$', uri_path) and not assume_no_home_pages:
                    continue

                title_part_counts.setdefault(title_part, {})
                title_part_counts[title_part]['solo'] = 1

            # this function needs to work whether or not the story has already been inserted into the db
            stories_id = story['stories_id'] if 'stories_id' in story else story['guid']

            title_part_counts.setdefault(title_part, {})

            title_part_counts[title_part].setdefault('count', 0)
            title_part_counts[title_part]['count'] += 1

            title_part_counts[title_part].setdefault('stories', {})
            title_part_counts[title_part]['stories'][stories_id] = story

    duplicate_stories = []
    log.warning(title_part_counts)
    for t in filter(lambda t: t.get('solo', False), title_part_counts.values()):
        num_stories = len(t['stories'])

        if num_stories > 1:
            dup_stories = t['stories'].values()
            if num_stories < 26 or _get_story_date_range(dup_stories) < 7 * 86400:
                duplicate_stories.append(dup_stories)
            else:
                dup_title = t['stories'].values()[0]['title']
                log.debug("Cowardly refusing to mark num_stories stories as dups [%s]" % dup_title)

    return duplicate_stories
