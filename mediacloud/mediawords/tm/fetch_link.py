"""This is the code backing the topic_fetch_link job, which fetches links and generates mc stories from them."""

import datetime
import re
import socket
import time
import traceback
import typing

from mediawords.db import DatabaseHandler
import mediawords.tm.stories
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
import mediawords.util.url
from mediawords.util.web.user_agent.request.request import Request
from mediawords.util.web.user_agent.response.response import Response
from mediawords.util.web.user_agent.throttled import ThrottledUserAgent, McThrottledDomainException

log = create_logger(__name__)


# if the network is down, wait this many seconds before retrying the fetch
DEFAULT_NETWORK_DOWN_TIMEOUT = 30

# connect to port 80 on this host to check for network connectivity
DEFAULT_NETWORK_DOWN_HOST = 'www.google.com'
DEFAULT_NETWORK_DOWN_PORT = 80

# states indicating the result of fetch_topic_url
FETCH_STATE_PENDING = 'pending'
FETCH_STATE_REQUEST_FAILED = 'request failed'
FETCH_STATE_CONTENT_MATCH_FAILED = 'content match failed'
FETCH_STATE_STORY_MATCH = 'story match'
FETCH_STATE_STORY_ADDED = 'story added'
FETCH_STATE_PYTHON_ERROR = 'python error'
FETCH_STATE_REQUEUED = 'requeued'
FETCH_STATE_KILLED = 'killed'


class McTMFetchLinkException(Exception):
    """Default exception for this package."""

    pass


def _network_is_down(host: str=DEFAULT_NETWORK_DOWN_HOST, port: int=DEFAULT_NETWORK_DOWN_PORT) -> bool:
    """Test whether the internet is accessible by trying to connect to prot 80 on the given host."""
    try:
        socket.create_connection((host, port))
        return False
    except OSError:
        pass

    return True


def fetch_url(
        db: DatabaseHandler,
        url: str,
        network_down_host: str=DEFAULT_NETWORK_DOWN_HOST,
        network_down_port: str=DEFAULT_NETWORK_DOWN_PORT,
        network_down_timeout: int=DEFAULT_NETWORK_DOWN_TIMEOUT,
        domain_timeout: typing.Optional[int]=None) -> typing.Optional[Request]:
    """Fetch a url and return the content.

    If fetching the url results in a 400 error, check whether the network_down_host is accessible.  If so,
    return the errored response.  Otherwise, wait network_down_timeout seconds and try again.

    This function catches McGetException and returns a dummy 400 Response object.

    Arguments:
    db - db handle
    url - url to fetch
    network_down_host - host to check if network is down on error
    network_down_port - port to check if network is down on error
    network_down_timeout - seconds to wait if the network is down
    domain_timeout - value to pass to ThrottledUserAgent()

    Returns:
    Response object
    """
    while True:
        ua = ThrottledUserAgent(db, domain_timeout=domain_timeout)

        try:
            response = ua.get_follow_http_html_redirects(url)
        except mediawords.util.web.user_agent.McGetFollowHTTPHTMLRedirectsException:
            response = Response(400, 'bad url', {}, 'not a http url')

        if response.is_success():
            return response

        if response.code() == 400 and _network_is_down(network_down_host, network_down_port):
            log.warning("Response failed with %s and network is down.  Waiting to retry ..." % (url,))
            time.sleep(network_down_timeout)
        else:
            return response


def content_matches_topic(content: str, topic: dict, assume_match: bool=False) -> bool:
    """Test whether the content matches the topic['pattern'] regex.

    Only check the first megabyte of the string to avoid the occasional very long regex check.

    Arguments:
    content - text content
    topic - topic dict from db
    assume_match - assume that the content matches

    Return:
    True if the content matches the topic pattern

    """
    if assume_match:
        return True

    content = content[0:1024 * 1024]

    return re.search(topic['pattern'], content, flags=re.I | re.X | re.S) is not None


def get_seeded_content(db: DatabaseHandler, topic_fetch_url: dict) -> typing.Optional[str]:
    """Return content for this url and topic in topic_seed_urls.

    Arguments:
    db - db handle
    topic_fetch_url - topic_fetch_url dict from db

    Returns:
    dummy response object

    """
    r = db.query(
        "select content from topic_seed_urls where topics_id = %(a)s and url = %(b)s and content is not null",
        {'a': topic_fetch_url['topics_id'], 'b': topic_fetch_url['url']}).flat()

    if len(r) == 0:
        return None

    response = Response(code=200, message='OK', headers={}, data=r[0])
    response.set_request(Request('GET', topic_fetch_url['url']))

    return response


def get_failed_urls(db: DatabaseHandler, topic: dict, urls: list) -> list:
    """Return the links from the set without FETCH_STATE_REQUEST_FAILED or FETCH_STATE_CONTENT_MATCH_FAILED states.

    Arguments:
    db - db handle
    topic - topic dict from db
    urls - string urls

    Returns:
    a list of the urls that do not have fetch failes
    """
    topic = decode_object_from_bytes_if_needed(topic)
    urls = decode_object_from_bytes_if_needed(urls)

    r = db.query(
        """
        select url
            from topic_fetch_urls
            where
                topics_id = %(a)s and
                state in (%(b)s, %(c)s) and
                url = any(%(d)s)
        """,
        {
            'a': topic['topics_id'],
            'b': FETCH_STATE_REQUEST_FAILED,
            'c': FETCH_STATE_CONTENT_MATCH_FAILED,
            'd': urls
        }).hashes()

    failed_urls = [u['url'] for u in r]

    return failed_urls


def fetch_topic_url(db: DatabaseHandler, topic_fetch_urls_id: int, domain_timeout: typing.Optional[int]=None) -> None:
    """Fetch a url for a topic and create a media cloud story from it if its content matches the topic pattern.

    Update the following fields in the topic_fetch_urls row:

    code - the status code of the http response
    fetch_date - the current time
    state - one of the FETCH_STATE_* constatnts
    message - message related to the state (eg. HTTP message for FETCH_STATE_REQUEST_FAILED)
    stories_id - the id of the story generated from the fetched content, or null if no story created'

    If the state is anything but FETCH_STATE_PENDING or FETCH_STATE_REQUEUED, return without doing anything.

    If there is content for the corresponding url and topics_id in topic_seed_urls, use that content instead of
    fetching the url.

    This function catches almost all possible exceptions and stashes them topic_fetch_urls along with a state of
    FETCH_STATE_PYTHON_ERROR

    Arguments:
    db - db handle
    topic_fetch_urls_id - id of topic_fetch_urls row
    domain_timeout - pass through to fech_link

    Returns:
    None

    """
    try:
        topic_fetch_url = db.require_by_id('topic_fetch_urls', topic_fetch_urls_id)
        log.info("fetch_link: %s" % topic_fetch_url['url'])

        # don't reprocess already processed urls
        if topic_fetch_url['state'] not in (FETCH_STATE_PENDING, FETCH_STATE_REQUEUED):
            return

        topic = db.require_by_id('topics', topic_fetch_url['topics_id'])
        topic_fetch_url['fetch_date'] = datetime.datetime.now()

        response = get_seeded_content(db, topic_fetch_url)
        if response is None:
            response = fetch_url(db, topic_fetch_url['url'], domain_timeout=domain_timeout)
            log.debug("%d response returned for url: %s" % (response.code(), topic_fetch_url['url']))
        else:
            log.debug("seeded content found for url: %s" % topic_fetch_url['url'])

        response_url = response.request().url() if response.request() else None

        topic_fetch_url['code'] = response.code()

        story_match = mediawords.tm.stories.get_story_match(
            db=db, url=topic_fetch_url['url'], redirect_url=response_url)
        content = response.decoded_content()

        if not response.is_success():
            topic_fetch_url['state'] = FETCH_STATE_REQUEST_FAILED
            topic_fetch_url['message'] = response.message()
        elif story_match is not None:
            topic_fetch_url['state'] = FETCH_STATE_STORY_MATCH
            topic_fetch_url['stories_id'] = story_match['stories_id']
        elif not content_matches_topic(content=content, topic=topic, assume_match=topic_fetch_url['assume_match']):
            topic_fetch_url['state'] = FETCH_STATE_CONTENT_MATCH_FAILED
        else:
            try:
                url = response.request().url() if response.request() is not None else topic_fetch_url['url']
                story = mediawords.tm.stories.generate_story(
                    db=db,
                    content=content,
                    url=url)
                topic_fetch_url['state'] = FETCH_STATE_STORY_ADDED
                topic_fetch_url['stories_id'] = story['stories_id']
            except mediawords.tm.stories.McTMStoriesDuplicateException:
                # may get a unique constraint error for the story addition within the media source.  that's fine
                # because it means the story is already in the database and we just need to match it again.
                topic_fetch_url['state'] = FETCH_STATE_STORY_MATCH
                story_match = mediawords.tm.stories.get_story_match(
                    db=db, url=topic_fetch_url['url'], redirect_url=response_url)
                if story_match is None:
                    raise McTMFetchLinkException("Unable to find matching story after unique constraint error.")
                topic_fetch_url['stories_id'] = story_match['stories_id']
    except McThrottledDomainException as e:
        raise e
    except Exception as e:
        topic_fetch_url['state'] = FETCH_STATE_PYTHON_ERROR
        topic_fetch_url['message'] = traceback.format_exc()
        log.warning('topic_fetch_url %s failed: %s' % (topic_fetch_url['url'], topic_fetch_url['message']))

    db.update_by_id('topic_fetch_urls', topic_fetch_url['topic_fetch_urls_id'], topic_fetch_url)
