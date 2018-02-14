"""Various functions for extracting links from stories and for storing them in topics."""

from bs4 import BeautifulSoup
import re
import typing

from mediawords.db import DatabaseHandler
import mediawords.dbi.downloads
from mediawords.util.log import create_logger

log = create_logger(__name__)


_IGNORE_LINK_PATTERN = (
    '(www.addtoany.com)|(novostimira.com)|(ads\.pheedo)|(www.dailykos.com\/user)|'
    '(livejournal.com\/(tag|profile))|(sfbayview.com\/tag)|(absoluteastronomy.com)|'
    '(\/share.*http)|(digg.com\/submit)|(facebook.com.*mediacontentsharebutton)|'
    '(feeds.wordpress.com\/.*\/go)|(sharetodiaspora.github.io\/)|(iconosquare.com)|'
    '(unz.com)|(answers.com)|(downwithtyranny.com\/search)|(scoop\.?it)|(sco\.lt)|'
    '(pronk.*\.wordpress\.com\/(tag|category))|(wn\.com)|(pinterest\.com\/pin\/create)|(feedblitz\.com)|(atomz.com)')


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

        if re.search(_IGNORE_LINK_PATTERN, url, flags=re.I) is not None:
            continue

        if not mediawords.util.url.is_http_url(url):
            continue

        url = re.sub(r'www[a-z0-9]+.nytimes', 'www.nytimes', url, flags=re.I)

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

        url = re.sub('youtube-embed', 'youtube', url)

        links.append(url)

    return links


def get_extracted_html(db: DatabaseHandler, story: dict) -> str:
    """Get the extracted html for the story.

    We don't store the extracted html of a story, so we have to get the first download assoicated with the story
    and run the extractor on it.

    """
    download = db.query(
        "select * from downloads where stories_id = %(a)s order by downloads_id limit 1",
        {'a': story['stories_id']}).hash()

    extractor_results = mediawords.dbi.downloads.extract(db, download, use_cache=True)
    return extractor_results['extracted_html']


def get_links_from_story_text(db: DatabaseHandler, story: dict) -> typing.List[str]:
    """Get all urls that appear in the text or description of the story using a simple regex."""
    download_texts = db.query(
        "select dt.* from downloads d join download_texts dt using ( downloads_id ) where stories_id = %(a)s",
        {'a': story['stories_id']}).hashes()

    story_text = ' '.join([dt['download_text'] for dt in download_texts])

    story_text = ' '.join((story['title'], story['description'], story_text))

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
    extracted_html = get_extracted_html(db, story)

    html_links = get_links_from_html(extracted_html)
    text_links = get_links_from_story_text(db, story)
    youtube_links = get_youtube_embed_links(db, story)

    links = html_links + text_links + youtube_links

    links = list(filter(lambda x: re.search(_IGNORE_LINK_PATTERN, x, flags=re.I) is None, links))

    link_lookup = {}
    for url in links:
        link_lookup[mediawords.util.url.normalize_url_lossy(url)] = url

    links = link_lookup.values()

    return links


def extract_links_for_topic_story(db: DatabaseHandler, story: dict, topic: dict) -> None:
    """
    Extract links from a story and insert them into the topic_links table for the given topic.

    After the story is processed, set topic_stories.spidered to true for that story.  Calls get_links_from_story
    on each story.

    Arguments:
    db - db handle
    story - story dict from db
    topic - topic dict from db

    Returns:
    None

    """
    log.info("mining %s %s for topic %s .." % (story['title'], story['url'], topic['name']))

    links = get_links_from_story(db, story)

    for link in links:
        topic_link = {
            'topics_id': topic['topics_id'],
            'stories_id': story['stories_id'],
            'url': link
        }

        db.create('topic_links', topic_link)

    db.query(
        "update topic_stories set link_mined = 't' where stories_id = %(a)s and topics_id = %(b)s",
        {'a': story['stories_id'], 'b': topic['topics_id']})
