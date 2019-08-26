"""Various functions for extracting links from stories and for storing them in topics."""

import re
import traceback
import typing

from bs4 import BeautifulSoup

from mediawords.db import DatabaseHandler
import mediawords.dbi.downloads
import mediawords.key_value_store.amazon_s3
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments
import mediawords.tm.domains
from mediawords.util.log import create_logger
from mediawords.util.url import is_http_url

log = create_logger(__name__)

# ignore any list that match the below patterns.  the sites below are most social sharing button links of
# various kinds, along with some content spam sitesand a couple of sites that confuse the spider with too
# many domain alternatives.
IGNORE_LINK_PATTERN = (
    r'(?:www.addtoany.com)|(?:novostimira.com)|(?:ads\.pheedo)|(?:www.dailykos.com\/user)|'
    r'(?:livejournal.com\/(?:tag|profile))|(?:sfbayview.com\/tag)|(?:absoluteastronomy.com)|'
    r'(?:\/share.*http)|(?:digg.com\/submit)|(?:facebook.com.*mediacontentsharebutton)|'
    r'(?:feeds.wordpress.com\/.*\/go)|(?:sharetodiaspora.github.io\/)|(?:iconosquare.com)|'
    r'(?:unz.com)|(?:answers.com)|(?:downwithtyranny.com\/search)|(?:scoop\.?it)|(?:sco\.lt)|'
    r'(?:pronk.*\.wordpress\.com\/(?:tag|category))|(?:wn\.com)|(?:pinterest\.com\/pin\/create)|(?:feedblitz\.com)|'
    r'(?:atomz.com)|(?:unionpedia.org)|(?:http://politicalgraveyard.com)|(?:https?://api\.[^\/]+)|'
    r'(?:www.rumormillnews.com)|(?:tvtropes.org/pmwiki)|(?:twitter.com/account/suspended)|'
    r'(?:feedsportal.com)')


def get_links_from_html(html: str) -> typing.List[str]:
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


def get_youtube_embed_links(db: DatabaseHandler, story: dict) -> typing.List[str]:
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

    html = mediawords.dbi.downloads.fetch_content(db, download)

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


def get_extracted_html(db: DatabaseHandler, story: dict) -> str:
    """Get the extracted html for the story.

    We don't store the extracted html of a story, so we have to get the first download assoicated with the story
    and run the extractor on it.

    """
    download = db.query(
        """

        SELECT *
        FROM downloads
        WHERE stories_id = %(a)s

          -- Don't look into partitions that we don't have to look at
          AND type = 'content'
          AND state = 'success'

        LIMIT 1

        """,
        {'a': story['stories_id']}).hash()

    extractor_results = mediawords.dbi.downloads.extract(db, download, PyExtractorArguments(use_cache=True))
    return extractor_results['extracted_html']


def get_links_from_story_text(db: DatabaseHandler, story: dict) -> typing.List[str]:
    """Get all urls that appear in the text or description of the story using a simple regex."""
    download_texts = db.query("""

        SELECT *
        FROM download_texts
        WHERE downloads_id IN (
            SELECT downloads_id
            FROM downloads
            WHERE stories_id = %(stories_id)s

              -- Don't look into partitions that we don't have to look at
              AND type = 'content'
              AND state = 'success'

        )
        ORDER BY download_texts_id

        """, {'stories_id': story['stories_id']}
    ).hashes()

    story_text = ' '.join([dt['download_text'] for dt in download_texts])

    story_text = story_text + ' ' + str(story['title']) if story['title'] is not None else story_text
    story_text = story_text + ' ' + str(story['description']) if story['description'] is not None else story_text

    links = []
    for url in re.findall(r'https?://[^\s\")]+', story_text):
        url = re.sub(r'\W+$', '', url)
        links.append(url)

    return links


def get_links_from_story(db: DatabaseHandler, story: dict) -> typing.List[str]:
    """Extract and return linksk from the story.

    Extracts generates a deduped list of links from get_links_from_html(), get_links_from_story_text(),
    and get_youtube_embed_links() for the given story.

    Arguments:
    db - db handle
    story - story dict from db

    Returns:
    list of urls

    """
    try:
        extracted_html = get_extracted_html(db, story)

        html_links = get_links_from_html(extracted_html)
        text_links = get_links_from_story_text(db, story)
        youtube_links = get_youtube_embed_links(db, story)

        all_links = html_links + text_links + youtube_links

        link_lookup = {}
        for url in filter(lambda x: re.search(IGNORE_LINK_PATTERN, x, flags=re.I) is None, all_links):
            link_lookup[mediawords.util.url.normalize_url_lossy(url)] = url

        links = list(link_lookup.values())

        return links
    except mediawords.key_value_store.amazon_s3.McAmazonS3StoreException:
        # we expect the fetch_content() to fail occasionally
        return []


def extract_links_for_topic_story(db: DatabaseHandler, story: dict, topic: dict) -> None:
    """
    Extract links from a story and insert them into the topic_links table for the given topic.

    After the story is processed, set topic_stories.spidered to true for that story.  Calls get_links_from_story
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
    try:
        log.info("mining %s %s for topic %s .." % (story['title'], story['url'], topic['name']))
        links = get_links_from_story(db, story)

        for link in links:
            if mediawords.tm.domains.skip_self_linked_domain_url(db, topic['topics_id'], story['url'], link):
                log.info("skipping self linked domain url...")
                continue

            topic_link = {
                'topics_id': topic['topics_id'],
                'stories_id': story['stories_id'],
                'url': link
            }

            db.create('topic_links', topic_link)
            mediawords.tm.domains.increment_domain_links(db, topic_link)

        link_mine_error = ''
    except Exception:
        link_mine_error = traceback.format_exc()

    db.query(
        """
        update topic_stories set link_mined = 't', link_mine_error = %(c)s
            where stories_id = %(a)s and topics_id = %(b)s
        """,
        {'a': story['stories_id'], 'b': topic['topics_id'], 'c': link_mine_error})
