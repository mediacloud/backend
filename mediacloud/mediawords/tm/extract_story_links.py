"""Extract links from a story and store them in the topic_links table."""

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
log = create_logger(__name__)


def get_boingboing_links(db: DatabaseHandler, story: dict) -> list:
    """Get links at end of boingboing link."""
    if 'boingboing.org' not in story['url']:
        return []

    download = db.query("select * from downloads where stories_id = %s", [story['stories_id']]).hash()

    if download is None:
        return []

    content = mediawords.dbi.downloads.fetch_content(db, download)

    (content, matched) = re.subn('((<div class="previously2">)|(class="sharePost")).*', '', content, flags='ms')
    if matched < 1:
        log.warning('unable to find end pattern')
        return []

    (content, matched) = re.subn('.*<a href[^>]*>[^<]*<\/a> at\s+\d+\:', '', content, flags='ms')
    if matched < 1:
        log.warning("unable to find begin pattern")
        return []

    return get_links_from_html(content, story['url'])


def get_first_download_content(db, story):
    """Get the html for the first download of the story.  fix the story download by redownloading as necessary."""

    download = db.query(<<END, story['stories_id']).hash
select d.* from downloads d where stories_id = ? order by downloads_id asc limit 1
END

    content_ref = None
    eval { content_ref = mediawords.dbi.downloads.fetch_content(db, download) }
    if $@:

        mediawords.dbi.stories.fix_story_downloads_if_needed(db, story)
        download = db.find_by_id('downloads', int( download['downloads_id']) )
        eval { content_ref = mediawords.dbi.downloads.fetch_content(db, download) }
        if $@:
            WARN "Error refetching content: $@"

    return content_ref ? $content_ref : ''

def get_youtube_embed_links(db, story):
    """ parse the full first download of the given story for youtube embeds"""

    html = get_first_download_content(db, story)

    links = []
    while ( html =~ /src\=[\'\"]((http:)?\/\/(www\.)?youtube(-nocookie)?\.com\/[^\'\"]*)/g )

        url = 1

        if not url =~ /^http/:

            url = "http:url/"

        url =~ s/\?.*//
        url =~ s/\/$//
        url =~ s/youtube-nocookie/youtube/i

        push(links, { 'url': url })

    return links

def get_extracted_html(db, story):
    """ get the extracted html for the story.  fix the story downloads by redownloading as necessary"""

    extracted_html = None
    eval { extracted_html = mediawords.dbi.stories.get_extracted_html_from_db(db, story) }
    if $@:

        logger.warning("extractor error: $@")
        mediawords.dbi.stories.fix_story_downloads_if_needed(db, story)
        eval { extracted_html = mediawords.dbi.stories.get_extracted_html_from_db(db, story) }

    return extracted_html

def get_links_from_story_text(db, story):
    """ get all urls that appear in the text or description of the story using a simple kludgy regex"""

    text = mediawords.dbi.stories.get_text(db, story)

    links = []
    while ( text =~ m~(https?://[^\s\")]+)~g )

        url = 1

        url =~ s/\W+$//

        push(links, { 'url': url })

    return links

def get_links_from_story(db, story):
    """ find any links in the extracted html or the description of the story."""

    INFO "mining story['title'] [story['url']] ..."

    extracted_html = get_extracted_html(db, story)

    links = get_links_from_html(extracted_html, story['url'])
    text_links = get_links_from_story_text(db, story)
    description_links = get_links_from_html(story['description'], story['url'])
    boingboing_links = get_boingboing_links(db, story)
    youtube_links = get_youtube_embed_links(db, story)

    my all_links = (links, text_links, description_links, boingboing_links)

    all_links = grep { _['url'] not ~ _ignore_link_pattern } all_links

    link_lookup = {}
    map { link_lookup->{ mediawords.util.url.normalize_url_lossy(_['url']) } = _ } all_links

    return [ values(link_lookup) ]


def extract_links(db: DatabaseHandler, story: dict, topic: dict) -> None:
    """
    Extract links from a story and story then in the topic_links table.

    Search in the description, story_text, and html for links.After the story is processed,
    set topic_stories.spidered to true for that story.

    Arguments:
    db - db handle
    story - story dict from db
    topic - topic dict from db

    Returns:
    None
    """
    pass
