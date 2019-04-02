"""Various functions for extracting links from stories and for storing them in topics."""

import re
import traceback
from typing import List

from bs4 import BeautifulSoup

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads.store import fetch_content
from mediawords.key_value_store.amazon_s3 import McAmazonS3StoreException
from mediawords.tm.domains import skip_self_linked_domain_url, increment_domain_links
from mediawords.util.extract_article_from_page import extract_article_html_from_page_html
from mediawords.util.log import create_logger
from mediawords.util.url import is_http_url, normalize_url_lossy
from mediawords.tm.ignore_link_pattern import IGNORE_LINK_PATTERN

log = create_logger(__name__)


def _get_links_from_html(html: str) -> List[str]:
    """Return a list of all links that appear in the html.

    Only return absolute urls, because we would rather get fewer internal media source links.  Also include embedded
    youtube video urls.

    Arguments:
    html - html to parse

    Returns:
    list of string urls

    """
    soup = BeautifulSoup(html, 'lxml')

    links = []

    # get everything with an href= element rather than just <a /> links
    for tag in soup.find_all(href=True):
        url = tag['href']

        if re.search(IGNORE_LINK_PATTERN, url, flags=re.I) is not None:
            continue

        if not is_http_url(url):
            continue

        url = re.sub(r'(https)?://www[a-z0-9]+.nytimes', r'\1://www.nytimes', url, flags=re.I)

        links.append(url)

    return links


def _get_youtube_embed_links(db: DatabaseHandler, story: dict) -> List[str]:
    """Parse youtube embedded video urls out of the full html of the story.

    This function looks for youtube embed links anywhere in the html of the story content, rather than just in the
    extracted html.  It aims to return a superset of all youtube embed links by returning every iframe src= attribute
    that includes the string 'youtube'.

    Arguments:
    db - db handle
    story - story dict from db

    Returns:
    list of string urls

    """
    download = db.query(
        "select * from downloads where stories_id = %(a)s order by stories_id limit 1",
        {'a': story['stories_id']}).hash()

    html = fetch_content(db, download)

    soup = BeautifulSoup(html, 'lxml')

    links = []
    for tag in soup.find_all('iframe', src=True):
        url = tag['src']

        if 'youtube' not in url:
            continue

        if not url.lower().startswith('http'):
            url = 'http:' + url

        url = url.strip()

        url = url.replace('youtube-embed', 'youtube')

        links.append(url)

    return links


def _get_extracted_html(db: DatabaseHandler, story: dict) -> str:
    """Get the extracted html for the story.

    We don't store the extracted html of a story, so we have to get the first download assoicated with the story
    and run the extractor on it.

    """

    # "download_texts" INT -> BIGINT join hack: convert parameter downloads_id to a constant array first
    download_texts = db.query("""
        SELECT download_text
        FROM download_texts
        WHERE downloads_id = ANY(
            ARRAY(
                SELECT downloads_id
                FROM downloads
                WHERE stories_id = %(stories_id)s
            )
        )
        ORDER BY downloads_id
    """, {'stories_id': story['stories_id']}).flat()

    html = ".\n\n".join(download_texts)

    extract = extract_article_html_from_page_html(html)
    extracted_html = extract['extracted_html']

    return extracted_html


def _get_links_from_story_text(db: DatabaseHandler, story: dict) -> List[str]:
    """Get all urls that appear in the text or description of the story using a simple regex."""
    download_ids = db.query("""
        SELECT downloads_id
        FROM downloads
        WHERE stories_id = %(stories_id)s
        """, {'stories_id': story['stories_id']}
                            ).flat()

    download_texts = db.query("""
        SELECT *
        FROM download_texts
        WHERE downloads_id = ANY(%(download_ids)s)
        ORDER BY download_texts_id
        """, {'download_ids': download_ids}
                              ).hashes()

    story_text = ' '.join([dt['download_text'] for dt in download_texts])

    story_text = story_text + ' ' + str(story['title']) if story['title'] is not None else story_text
    story_text = story_text + ' ' + str(story['description']) if story['description'] is not None else story_text

    links = []
    for url in re.findall(r'https?://[^\s\")]+', story_text):
        url = re.sub(r'\W+$', '', url)
        links.append(url)

    return links


def _get_links_from_story(db: DatabaseHandler, story: dict) -> List[str]:
    """Extract and return linksk from the story.

    Extracts generates a deduped list of links from _get_links_from_html(), _get_links_from_story_text(),
    and _get_youtube_embed_links() for the given story.

    Arguments:
    db - db handle
    story - story dict from db

    Returns:
    list of urls

    """
    try:
        extracted_html = _get_extracted_html(db, story)

        html_links = _get_links_from_html(extracted_html)
        text_links = _get_links_from_story_text(db, story)
        youtube_links = _get_youtube_embed_links(db, story)

        all_links = html_links + text_links + youtube_links

        link_lookup = {}
        for url in filter(lambda x: re.search(IGNORE_LINK_PATTERN, x, flags=re.I) is None, all_links):
            link_lookup[normalize_url_lossy(url)] = url

        links = list(link_lookup.values())

        return links
    except McAmazonS3StoreException:
        # we expect the fetch_content() to fail occasionally
        return []


def extract_links_for_topic_story(db: DatabaseHandler, stories_id: int, topics_id: int) -> None:
    """
    Extract links from a story and insert them into the topic_links table for the given topic.

    After the story is processed, set topic_stories.spidered to true for that story.  Calls _get_links_from_story()
    on each story.

    Almost all errors are caught by this function saved in topic_stories.link_mine_error.  In the case of an error
    topic_stories.link_mined is also set to true.

    Arguments:
    db - db handle
    story - story dict from db
    topic - topic dict from db

    Returns:
    None

    """
    story = db.require_by_id(table='stories', object_id=stories_id)
    topic = db.require_by_id(table='topics', object_id=topics_id)

    try:
        log.info("mining %s %s for topic %s .." % (story['title'], story['url'], topic['name']))
        links = _get_links_from_story(db, story)

        for link in links:
            if skip_self_linked_domain_url(db, topic['topics_id'], story['url'], link):
                log.info("skipping self linked domain url...")
                continue

            topic_link = {
                'topics_id': topic['topics_id'],
                'stories_id': story['stories_id'],
                'url': link
            }

            db.create('topic_links', topic_link)
            increment_domain_links(db, topic_link)

        link_mine_error = ''
    except Exception as ex:
        log.error(f"Link mining error: {ex}")
        link_mine_error = traceback.format_exc()

    db.query(
        """
        update topic_stories set link_mined = 't', link_mine_error = %(c)s
            where stories_id = %(a)s and topics_id = %(b)s
        """,
        {'a': story['stories_id'], 'b': topic['topics_id'], 'c': link_mine_error})
