"""This is the code backing the topic_fetch_link job, which fetches links and generates mc stories from them."""

import datetime
import re
import socket
import time
import typing

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
import mediawords.util.url
from mediawords.util.web.user_agent.throttled import ThrottledUserAgent

log = create_logger(__name__)


# if the network is down, wait this many seconds before retrying the fetch
_DEFAULT_NETWORK_DOWN_TIMEOUT = 10

# connect to port 80 on this host to check for network connectivity
_DEFAULT_NETWORK_DOWN_HOST = 'www.google.com'


def _network_is_down(host: str) -> bool:
    """Test whether the internet is accessible by trying to connect to prot 80 on the given host."""
    try:
        socket.create_connection((host, 80))
        return False
    except OSError:
        pass

    return True


def fetch_url(
        db: DatabaseHandler,
        url: str,
        network_down_host: str=_DEFAULT_NETWORK_DOWN_HOST,
        network_down_timeout: int=_DEFAULT_NETWORK_DOWN_TIMEOUT) -> typing.Optional[str]:
    """Fetch a url and return the content.

    If fetching the url results in a 400 error, check whether the network_down_host is accessible.  If so,
    return None.  Otherwise, wait network_down_timeout seconds and try again.

    Arguments:
    db - db handle
    url - url to fetch
    network_down_host - host to check if network is down on error
    network_down_timeout - seconds to wait if the network is down

    Returns:
    html of valid content or None if the response failed.
    """
    if not mediawords.util.url.is_http_url(url):
        log.debug("not an http url: %s" % (url,))
        return None

    while True:
        ua = ThrottledUserAgent(db)

        response = ua.get(url)

        if response.is_success:
            return response.decoded_content()

        if response.code() != 400 and _network_is_down():
            log.warning("Response failed with %s and network is down.  Waiting to retry ..." % (url,))
            time.sleep(network_down_timeout)
        else:
            return None


def _content_matches_topic(content: str, topic: dict, assume_match: bool=False) -> bool:
    """Test whether the content matches the topic['pattern'] regex.

    Only check the first megabyte of the string to avoid the occasional very long regex check.

    Arguments:
    content - text content
    topic - topic dict from db
    assume_match - assume that the content matches

    Return:
    True if the content matches the topic pattern

    """
    if topic_fetch_url['assume_match']:
        return True

    content = content[0:1024 * 1024]

    return re.search(topic['pattern'], content, flags=re.I | re.X | re.S) is not None


def fetch_topic_url(db: DatabaseHandler, topic_fetch_urls_id: int) -> None:
    """Fetch a url for a topic and create a media cloud story from it if its content matches the topic pattern.

    Update the following fields in the topic_fetch_urls row:

    code - the status code of the http response
    fetch_date - the current time
    state - one of the FETCH_STATE_* constatnts
    stories_id - the id of the story generated from the fetched content, or null if no story created'

    Arguments:
    db - db handle
    topic_fetch_urls_id - id of topic_fetch_urls row

    Returns:
    None

    """
    topic_fetch_url = db.require_by_id('topic_fetch_urls', topic_fetch_urls_id)
    topic = db.require_by_id('topics', topic_fetch_url['topic_fetch_urls_id'])
    topic_fetch_url['fetch_date'] = datetime.datetime.now()

    try:
        response = fetch_url(topic_fetch_url['url'])

        topic_fetch_url['code'] = response.code()

        redirect_story_match = mediawords.tm.story.get_story_match(
            db=db, url=topic_fetch_url['url'], redirect_url=response.request().url())
        content = response.decoded_content()

        if not response.is_success():
            topic_fetch_url['state'] = 'request failed'
        elif redirect_story_match is not None:
            topic_fetch_url['state'] = 'story match'
            topic_fetch_url['stories_id'] = redirect_story_match['stories_id']
        elif _content_matches_topic(content=content, topic=topic, assume_match=topic_fetch_url['assume_match']):
            topic_fetch_url['state'] = 'match failed'
        else:
            try:
                story = mediawords.tm.story.generate_story(
                    db=db,
                    content=content,
                    url=topic_fetch_url['url'],
                topic_fetch_url['state'] = 'story added'
                topic_fetch_url['stories_id'] = story['stories_id']
            except mediawords.tm.story.McTMGenerateStoryDuplicate:
                # may get dup url for the story addition within the media source.  that's fine because it means the
                # story is already in the database and we just need to match it again.
                topic_fetch_url['state'] = 'story match'
                story_match = mediawords.tm.story.get_story_match(
                    db=db, url=topic_fetch_url['url'], redirect_url=response.request().url())
                topic_fetch_url['stories_id'] = story_match['stories_id']

    except Exception as e:
        topic_fetch_url['state'] = 'python error'

    db.update_by_id('topic_fetch_urls', topic_fetch_url['topic_fetch_urls_id'], topic_fetch_url)
