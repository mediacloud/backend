import re
from typing import List

from furl import furl

from mediawords.db import DatabaseHandler
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.web.user_agent import UserAgent

from crawler_fetcher.handlers.feed_syndicated import DownloadFeedSyndicatedHandler

log = create_logger(__name__)


def _get_feed_url_from_itunes_podcasts_url(url: str) -> str:
    """
    Given a iTunes Podcasts URL, try to determine a RSS feed URL from it.

    :param url: iTunes Podcasts URL, e.g. https://podcasts.apple.com/lt/podcast/blah-blah/id1364954186?i=1000455255008
    :return: RSS feed URL that iTunes Podcasts uses, or original URL if it's not a iTunes Podcasts URL / feed URL can't
             be determined.
    """

    uri = furl(url)

    if uri.host not in {'podcasts.apple.com', 'itunes.apple.com'}:
        log.debug(f"URL '{url}' is not iTunes Podcasts URL.")
        return url

    # https://podcasts.apple.com/lt/podcast/blah-blah/id1364954186?i=1000455255008
    itunes_id = None
    for segment in reversed(uri.path.segments):
        match = re.match(r'^id(\d+?)$', segment)
        if match:
            itunes_id = match.group(1)
            break

    if not itunes_id:
        log.error(f"Unable to determine iTunes ID from URL '{url}'")
        return url

    ua = UserAgent()
    res = ua.get(f"https://itunes.apple.com/lookup?id={itunes_id}&entity=podcast")
    if not res.is_success():
        log.error(f"Unable to fetch iTunes Podcasts feed URL: {res.status_line()}")
        return url

    try:
        res_dict = res.decoded_json()
        if not isinstance(res_dict, dict):
            raise Exception("Result is not a dictionary")
    except Exception as ex:
        log.error(f"Unable to decode iTunes Podcasts feed JSON: {ex}")
        return url

    if res_dict.get('resultCount', None) != 1:
        log.error("Result count is not 1")
        return url

    results = res_dict.get('results', None)
    if not results:
        log.error("'results' not found in JSON response")
        return url

    if len(results) != 1:
        log.error("'results' is expected to have a single list item")
        return url

    feed_url = results[0].get('feedUrl', None)
    if not feed_url:
        log.error("'feedUrl' was not found in first row of 'results'")
        return url

    log.info(f"Resolved iTunes Podcasts URL '{url}' as '{feed_url}'")

    return feed_url


def _get_feed_url_from_google_podcasts_url(url: str) -> str:
    """
    Given a Google Podcasts URL, try to determine a RSS feed URL from it.

    :param url: Google Podcasts URL, e.g. https://podcasts.google.com/?feed=aHR0cHM6Ly93d3cucmVzaWRlbnRhZHZpc29yLm5ldC94
                bWwvcG9kY2FzdC54bWw&ved=0CAAQ4aUDahcKEwiot6W5hrnnAhUAAAAAHQAAAAAQAQ&hl=lt
    :return: RSS feed URL that Google Podcasts uses, or original URL if it's not a Google Podcasts URL / feed URL can't
             be determined.
    """

    uri = furl(url)

    if uri.host != 'podcasts.google.com':
        log.debug(f"URL '{url}' is not Google Podcasts URL.")
        return url

    if 'feed' not in uri.args:
        log.error(f"URL '{url}' doesn't have 'feed' parameter.")

    # Remove the rest of the arguments because they might lead to an episode page which doesn't have "data-feed"
    args = list(uri.args.keys())
    for arg in args:
        if arg != 'feed':
            del uri.args[arg]

    url = str(uri.url)

    ua = UserAgent()
    res = ua.get(url)
    if not res.is_success():
        log.error(f"Unable to fetch Google Podcasts feed URL: {res.status_line()}")
        return url

    html = res.decoded_content()

    # check whether this is an individual episode URL rather than the show's Google Podcasts homepage; the feed URL
    # doesn't appear on individual episode pages, so we need to spider to the show's Google Podcasts homepage to get it
    if '/episode/' in url:
        show_homepage = url.split('/episode/')[0]
        res = ua.get(show_homepage)
        if not res.is_success():
            log.error(f"Unable to fetch Google Podcasts feed URL: {res.status_line()}")
            return show_homepage
        else:
            html = res.decoded_content()

    # get show's feed URL from its Google Podcasts homepage
    match = re.search(r'c-data id="i3" jsdata=".*(https?://.+?);2', html, flags=re.IGNORECASE)
    if not match:
        log.error(f"Feed URL was not found in Google Podcasts feed page.")
        return url

    feed_url = match.group(1)

    log.info(f"Resolved Google Podcasts URL '{url}' as '{feed_url}'")

    return feed_url


class DownloadFeedPodcastHandler(DownloadFeedSyndicatedHandler):
    """Handler for 'podcast' feed downloads."""

    @classmethod
    def _download_url(cls, download: dict) -> str:
        url = download['url']

        # Resolve iTunes Podcasts and Google Podcasts URLs
        url = _get_feed_url_from_itunes_podcasts_url(url=url)
        url = _get_feed_url_from_google_podcasts_url(url=url)

        return url

    @classmethod
    def _add_content_download_for_new_stories(cls) -> bool:
        # podcast-fetch-transcript will create a content download after fetching a transcript
        return False

    def add_stories_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        story_ids = super().add_stories_from_feed(db=db, download=download, content=content)

        # Add a podcast-fetch-episode job for every newly added story
        for stories_id in story_ids:
            log.info(f"Adding a podcast episode fetch job for story {stories_id}...")
            JobBroker(queue_name='MediaWords::Job::Podcast::FetchEpisode').add_to_queue(stories_id=stories_id)

        return story_ids
