"""This is the code backing the topic_fetch_link job, which fetches links and generates mc stories from them."""

import datetime
from typing import Optional

import re
import time
import traceback
from dataclasses import dataclass
from http import HTTPStatus

from mediawords.db import DatabaseHandler
from mediawords.dbi.stories.stories import insert_story_urls
from mediawords.util.log import create_logger
from mediawords.util.network import tcp_port_is_open
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import is_http_url, normalize_url_lossy
from mediawords.util.web.user_agent.response.response import Response
from mediawords.util.web.user_agent.throttled import ThrottledUserAgent, McThrottledDomainException
from topics_base.domains import skip_self_linked_domain
from topics_base.stories import (
    url_has_binary_extension,
    get_story_match,
    generate_story,
    McTMStoriesDuplicateException,
    add_to_topic_stories,
)
from topics_base.fetch_link_utils import content_matches_topic, try_update_topic_link_ref_stories_id
from topics_base.fetch_states import (
    FETCH_STATE_PENDING,
    FETCH_STATE_REQUEST_FAILED,
    FETCH_STATE_CONTENT_MATCH_FAILED,
    FETCH_STATE_STORY_MATCH,
    FETCH_STATE_STORY_ADDED,
    FETCH_STATE_PYTHON_ERROR,
    FETCH_STATE_REQUEUED,
    FETCH_STATE_IGNORED,
    FETCH_STATE_SKIPPED,
    FETCH_STATE_TWEET_PENDING,
)
from topics_base.twitter_url import parse_status_id_from_url, parse_screen_name_from_user_url
from topics_base.ignore_link_pattern import IGNORE_LINK_PATTERN

log = create_logger(__name__)

# set to true to use topic_fetch_urls.message to track current activity of each fetch_link job
_USE_TFU_DEBUG_MESSAGES = False

# if the network is down, wait this many seconds before retrying the fetch
DEFAULT_NETWORK_DOWN_TIMEOUT = 30

# connect to port 80 on this host to check for network connectivity
DEFAULT_NETWORK_DOWN_HOST = 'www.google.com'
DEFAULT_NETWORK_DOWN_PORT = 80


class McTMFetchLinkException(Exception):
    """Default exception for this package."""
    pass


# Creating UserAgent's "fake" responses is just a bit too awkward because we have to go know how Response is implemented
# so use our own response object storing just the parts that we need
@dataclass
class FetchLinkResponse(object):
    """Response after fetching an URL."""

    url: str
    """Originally requested URL."""

    is_success: bool
    """Whether or not the request was successful."""

    code: int
    """HTTP response code, e.g. 200."""

    message: str
    """HTTP response message, e.g. 'OK'."""

    content: str
    """Decoded content of the response."""

    last_requested_url: Optional[str] = None
    """Last requested URL that led to this response (in case of a redirect cycle)."""

    @classmethod
    def from_useragent_response(cls, url: str, response: Response):
        return cls(
            url=url,
            is_success=response.is_success(),
            code=response.code(),
            message=response.message(),
            content=response.decoded_content(),
            last_requested_url=response.request().url() if response.request() else None,
        )


def _make_dummy_bypassed_response(url: str) -> FetchLinkResponse:
    """Given a url, make and return a response object with that url and empty content."""
    return FetchLinkResponse(
        url=url,
        is_success=True,
        code=HTTPStatus.OK.value,
        message=HTTPStatus.OK.phrase,
        content='',
        last_requested_url=url,
    )


def _fetch_url(
        db: DatabaseHandler,
        url: str,
        network_down_host: str = DEFAULT_NETWORK_DOWN_HOST,
        network_down_port: int = DEFAULT_NETWORK_DOWN_PORT,
        network_down_timeout: int = DEFAULT_NETWORK_DOWN_TIMEOUT,
        domain_timeout: Optional[int] = None) -> FetchLinkResponse:
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
    if url_has_binary_extension(url):
        return _make_dummy_bypassed_response(url)

    while True:
        ua = ThrottledUserAgent(db, domain_timeout=domain_timeout)

        if is_http_url(url):
            ua_response = ua.get_follow_http_html_redirects(url)
            response = FetchLinkResponse.from_useragent_response(url, ua_response)
        else:
            log.warning(f"URL is not HTTP(s), returning dummy response: {url}")
            response = FetchLinkResponse(
                url=url,
                is_success=False,
                code=HTTPStatus.BAD_REQUEST.value,
                message=HTTPStatus.BAD_REQUEST.phrase,
                content='bad url',
                last_requested_url=None,
            )

        if response.is_success:
            return response

        if response.code == HTTPStatus.BAD_REQUEST.value and not tcp_port_is_open(port=network_down_port,
                                                                                  hostname=network_down_host):
            log.warning("Response failed with %s and network is down.  Waiting to retry ..." % (url,))
            time.sleep(network_down_timeout)
        else:
            return response


def _story_matches_topic(
        db: DatabaseHandler,
        story: dict,
        topic: dict,
        assume_match: bool = False,
        redirect_url: str = None) -> bool:
    """Test whether the story sentences or metadata of the story match the topic['pattern'] regex.

    Arguments:
    db - database handle
    story - story to match against topic pattern
    topic - topic to match against
    redirect_url - alternate url for story


    Return:
    True if the story matches the topic pattern

    """
    if assume_match:
        return True

    for field in ['title', 'description', 'url']:
        if content_matches_topic(story[field], topic):
            return True

    if redirect_url and content_matches_topic(redirect_url, topic):
        return True

    sentences = db.query(
        "SELECT sentence FROM story_sentences WHERE stories_id = %(a)s",
        {'a': story['stories_id']}).flat()

    text = ' '.join(sentences)

    if content_matches_topic(text, topic):
        return True


def _is_not_topic_story(db: DatabaseHandler, topic_fetch_url: dict) -> bool:
    """Return True if the story is not in topic_stories for the given topic."""
    if 'stories_id' not in topic_fetch_url:
        return True

    ts = db.query(
        "SELECT * FROM topic_stories WHERE stories_id = %(a)s AND topics_id = %(b)s",
        {'a': topic_fetch_url['stories_id'], 'b': topic_fetch_url['topics_id']}).hash()

    return ts is None


# return true if the domain of the story url matches the domain of the medium url
def _get_seeded_content(db: DatabaseHandler, topic_fetch_url: dict) -> Optional[FetchLinkResponse]:
    """Return content for this url and topic in topic_seed_urls.

    Arguments:
    db - db handle
    topic_fetch_url - topic_fetch_url dict from db

    Returns:
    dummy response object

    """
    r = db.query(
        "SELECT content FROM topic_seed_urls WHERE topics_id = %(a)s AND url = %(b)s AND content IS NOT NULL",
        {'a': topic_fetch_url['topics_id'], 'b': topic_fetch_url['url']}).flat()

    if len(r) == 0:
        return None

    return FetchLinkResponse(
        url=topic_fetch_url['url'],
        is_success=True,
        code=HTTPStatus.OK.value,
        message=HTTPStatus.OK.phrase,
        content=r[0],
        last_requested_url=topic_fetch_url['url'],
    )


def _get_failed_url(db: DatabaseHandler, topics_id: int, url: str) -> Optional[dict]:
    """Return the links from the set without FETCH_STATE_REQUEST_FAILED or FETCH_STATE_CONTENT_MATCH_FAILED states.

    Arguments:
    db - db handle
    topic - topic dict from db
    urls - string urls

    Returns:

    a list of the topic_fetch_url dicts that do not have fetch fails
    """
    if isinstance(topics_id, bytes):
        topics_id = decode_object_from_bytes_if_needed(topics_id)

    topics_id = int(topics_id)
    url = decode_object_from_bytes_if_needed(url)

    urls = list({url, normalize_url_lossy(url)})

    failed_url = db.query(
        """
        SELECT *
        FROM topic_fetch_urls
        WHERE 
            url = any(array(select unnest(%(urls)s))) and
            topics_id = %(topics_id)s and
            state IN (%(fetch_state_1)s, %(fetch_state_2)s)
        LIMIT 1
        """,
        {
            'urls': urls,
            'topics_id': topics_id,
            'fetch_state_1': FETCH_STATE_REQUEST_FAILED,
            'fetch_state_2': FETCH_STATE_CONTENT_MATCH_FAILED,
        }
    ).hash()

    return failed_url


def _update_tfu_message(db: DatabaseHandler, topic_fetch_url: dict, message: str) -> None:
    """Update the topic_fetch_url.message field in the database."""
    if _USE_TFU_DEBUG_MESSAGES:

        db.query("""
            UPDATE topic_fetch_urls SET
                message = %(message)s
            WHERE
                topics_id = %(topics_id)s AND
                topic_fetch_urls_id = %(topic_fetch_urls_id)s
        """, {
            'topics_id': topic_fetch_url['topics_id'],
            'topic_fetch_urls_id': topic_fetch_url['topic_fetch_urls_id'],
            'message': message,
        })


def _ignore_link_pattern(url: Optional[str]) -> bool:
    """Return true if the url or redirect_url matches the ignore link pattern."""
    if url is None:
        return False

    p = IGNORE_LINK_PATTERN
    nu = normalize_url_lossy(url)

    if re.search(p, url, re.I) or re.search(p, nu, re.I):
        return True
    else:
        return False


def _get_pending_state(topic_fetch_url: dict) -> str:
    """Return a state if this url should be put in a pending state for another job queue (eg fetch_twitter_urls)."""
    url = topic_fetch_url['url']
    if parse_status_id_from_url(url) or parse_screen_name_from_user_url(url):
        return FETCH_STATE_TWEET_PENDING


def _try_fetch_topic_url(
        db: DatabaseHandler,
        topic_fetch_url: dict,
        domain_timeout: Optional[int] = None) -> None:
    """Implement the logic of fetch_topic_url without the try: or the topic_fetch_url update."""

    log.info(f"Trying to fetch topic URL {topic_fetch_url['url']}...")

    # don't reprocess already processed urls
    if topic_fetch_url['state'] not in (FETCH_STATE_PENDING, FETCH_STATE_REQUEUED):
        log.info(f"URL's state '{topic_fetch_url['state']}' is not pending or requeued, not refetching")
        return

    log.info("Checking ignore links...")
    _update_tfu_message(db, topic_fetch_url, "checking ignore links")
    if _ignore_link_pattern(topic_fetch_url['url']):
        log.info("Link is to be ignored, returning")
        topic_fetch_url['state'] = FETCH_STATE_IGNORED
        topic_fetch_url['code'] = 403
        return

    log.info("Checking failed URL...")
    _update_tfu_message(db, topic_fetch_url, "checking failed url")
    failed_url = _get_failed_url(db, topic_fetch_url['topics_id'], topic_fetch_url['url'])
    if failed_url:
        log.info("URL is failed, returning")
        topic_fetch_url['state'] = failed_url['state']
        topic_fetch_url['code'] = failed_url['code']
        topic_fetch_url['message'] = failed_url['message']
        return

    log.info("Checking self-linked domain...")
    _update_tfu_message(db, topic_fetch_url, "checking self linked domain")
    if skip_self_linked_domain(db, topic_fetch_url):
        log.info("Link is self-linked domain, returning")
        topic_fetch_url['state'] = FETCH_STATE_SKIPPED
        topic_fetch_url['code'] = 403
        return

    log.info(f"Fetching topic {topic_fetch_url['topics_id']}...")
    topic = db.require_by_id('topics', topic_fetch_url['topics_id'])
    topic_fetch_url['fetch_date'] = datetime.datetime.now()

    story_match = None

    # this match is relatively expensive, so only do it on the first 'pending' request and not the potentially
    # spammy 'requeued' requests
    log.info("Checking story match...")
    _update_tfu_message(db, topic_fetch_url, "checking story match")
    if topic_fetch_url['state'] == FETCH_STATE_PENDING:
        log.info("URL is in pending state, getting story match...")
        story_match = get_story_match(db=db, url=topic_fetch_url['url'])

        # try to match the story before doing the expensive fetch
        if story_match is not None:
            log.info(f"Matched story {story_match['stories_id']}, returning")
            topic_fetch_url['state'] = FETCH_STATE_STORY_MATCH
            topic_fetch_url['code'] = 200
            topic_fetch_url['stories_id'] = story_match['stories_id']
            return

    # check whether we want to delay fetching for another job, eg. fetch_twitter_urls
    log.info("Checking for pending state...")
    pending_state = _get_pending_state(topic_fetch_url)
    if pending_state:
        log.info("URL is in pending state, returning")
        topic_fetch_url['state'] = pending_state
        return

    # get content from either the seed or by fetching it
    log.info("Checking seeded content...")
    _update_tfu_message(db, topic_fetch_url, "checking seeded content")
    response = _get_seeded_content(db, topic_fetch_url)
    if response is None:
        log.info("Seeded content not found, fetching URL...")
        _update_tfu_message(db, topic_fetch_url, "fetching content")
        response = _fetch_url(db, topic_fetch_url['url'], domain_timeout=domain_timeout)
        log.info(f"{response.code} response returned")
    else:
        log.debug(f"Seeded content found for URL: {topic_fetch_url['url']}")

    content = response.content

    fetched_url = topic_fetch_url['url']
    response_url = response.last_requested_url

    if fetched_url != response_url:
        log.info(
            f"Fetched URL {fetched_url} is not the same as response URL {response_url}, testing for ignore link pattern"
        )
        if _ignore_link_pattern(response_url):
            log.info("Ignore link pattern matched, returning")
            topic_fetch_url['state'] = FETCH_STATE_IGNORED
            topic_fetch_url['code'] = 403
            return

        log.info("Checking story match for redirect URL...")
        _update_tfu_message(db, topic_fetch_url, "checking story match for redirect_url")
        story_match = get_story_match(db=db, url=fetched_url, redirect_url=response_url)

    topic_fetch_url['code'] = response.code

    assume_match = topic_fetch_url['assume_match']

    log.info("Checking content match...")
    _update_tfu_message(db, topic_fetch_url, "checking content match")
    if not response.is_success:
        log.info("Request failed")
        topic_fetch_url['state'] = FETCH_STATE_REQUEST_FAILED
        topic_fetch_url['message'] = response.message
    elif story_match is not None:
        log.info(f"Story {story_match['stories_id']} matched")
        topic_fetch_url['state'] = FETCH_STATE_STORY_MATCH
        topic_fetch_url['stories_id'] = story_match['stories_id']
    elif not content_matches_topic(content=content, topic=topic, assume_match=assume_match):
        log.info("Content matched")
        topic_fetch_url['state'] = FETCH_STATE_CONTENT_MATCH_FAILED
    else:
        log.info("Nothing matched, generating story...")

        try:
            _update_tfu_message(db, topic_fetch_url, "generating story")
            url = response_url if response_url is not None else fetched_url

            log.info("Creating story...")
            story = generate_story(db=db, content=content, url=url)
            log.info(f"Created story {story['stories_id']}")

            topic_fetch_url['stories_id'] = story['stories_id']
            topic_fetch_url['state'] = FETCH_STATE_STORY_ADDED

        except McTMStoriesDuplicateException:

            log.info("Duplicate story found, checking for story match on unique constraint error...")

            # may get a unique constraint error for the story addition within the media source.  that's fine
            # because it means the story is already in the database and we just need to match it again.
            _update_tfu_message(db, topic_fetch_url, "checking for story match on unique constraint error")
            topic_fetch_url['state'] = FETCH_STATE_STORY_MATCH
            story_match = get_story_match(db=db, url=fetched_url, redirect_url=response_url)
            if story_match is None:
                message = "Unable to find matching story after unique constraint error."
                log.error(message)
                raise McTMFetchLinkException(message)

            log.info(f"Matched story {story_match['stories_id']}")
            topic_fetch_url['stories_id'] = story_match['stories_id']

        log.info("Done generating story")

    _update_tfu_message(db, topic_fetch_url, "_try_fetch_url done")

    log.info(f"Done trying to fetch topic URL {topic_fetch_url['url']}.")


def fetch_topic_url(db: DatabaseHandler, topic_fetch_urls_id: int, domain_timeout: Optional[int] = None) -> None:
    """Fetch a url for a topic and create a media cloud story from it if its content matches the topic pattern.

    Update the following fields in the topic_fetch_urls row:

    code - the status code of the http response
    fetch_date - the current time
    state - one of the FETCH_STATE_* constatnts
    message - message related to the state (eg. HTTP message for FETCH_STATE_REQUEST_FAILED)
    stories_id - the id of the story generated from the fetched content, or null if no story created'

    If topic_links_id is present in the topic_fetch_url and if a story was added or matched, assign the resulting
    topic_fetch_urls.stories_id to topic_links.ref_stories_id.

    If the state is anything but FETCH_STATE_PENDING or FETCH_STATE_REQUEUED, return without doing anything.

    If there is content for the corresponding url and topics_id in topic_seed_urls, use that content instead of
    fetching the url.

    This function catches almost all possible exceptions and stashes them topic_fetch_urls along with a state of
    FETCH_STATE_PYTHON_ERROR

    Arguments:
    db - db handle
    topic_fetch_urls_id - id of topic_fetch_urls row
    domain_timeout - pass through to fetch_link

    Returns:
    None

    """
    topic_fetch_url = db.require_by_id('topic_fetch_urls', topic_fetch_urls_id)

    try:
        log.info("fetch_link: %s" % topic_fetch_url['url'])
        _try_fetch_topic_url(db=db, topic_fetch_url=topic_fetch_url, domain_timeout=domain_timeout)

        if topic_fetch_url['topic_links_id'] and topic_fetch_url['stories_id']:
            try_update_topic_link_ref_stories_id(db, topic_fetch_url)

        if 'stories_id' in topic_fetch_url and topic_fetch_url['stories_id'] is not None:
            story = db.require_by_id('stories', topic_fetch_url['stories_id'])
            topic = db.require_by_id('topics', topic_fetch_url['topics_id'])
            redirect_url = topic_fetch_url['url']
            assume_match = topic_fetch_url['assume_match']
            if _is_not_topic_story(db, topic_fetch_url):
                log.info("is not topic story")
                if _story_matches_topic(db, story, topic, redirect_url=redirect_url, assume_match=assume_match):
                    log.info("adding story to topic...")
                    add_to_topic_stories(db, story, topic)

            # add redirect_url as a lookup url for the story, if it is different from the story url
            if not redirect_url == topic_fetch_url['url']:
                insert_story_urls(db, story, redirect_url)

        if topic_fetch_url['topic_links_id'] and topic_fetch_url['stories_id']:
            try_update_topic_link_ref_stories_id(db, topic_fetch_url)

    except McThrottledDomainException as ex:
        raise ex

    except Exception as ex:
        log.error("Error while fetching URL {}: {}".format(topic_fetch_url, ex))

        topic_fetch_url['state'] = FETCH_STATE_PYTHON_ERROR
        topic_fetch_url['message'] = traceback.format_exc()
        log.warning('topic_fetch_url %s failed: %s' % (topic_fetch_url['url'], topic_fetch_url['message']))

    db.query(
        """
            UPDATE topic_fetch_urls SET
                url = %(url)s,
                code = %(code)s,
                fetch_date = %(fetch_date)s,
                state = %(state)s,
                message = %(message)s,
                stories_id = %(stories_id)s,
                assume_match = %(assume_match)s,
                topic_links_id = %(topic_links_id)s
            WHERE
                topics_id = %(topics_id)s AND
                topic_fetch_urls_id = %(topic_fetch_urls_id)s
        """,
        topic_fetch_url
    )


def fetch_topic_url_update_state(db: DatabaseHandler,
                                 topics_id: int,
                                 topic_fetch_urls_id: int,
                                 domain_timeout: Optional[int] = None) -> bool:
    """Tries fetch_topic_url() and updates state.

    Returns True if job completed and does not have to be requeued.

    Returns False if job was throttled and has to be requeued.

    Raises exception on other errors (after updating state).
    """
    try:
        fetch_topic_url(
            db=db,
            topic_fetch_urls_id=topic_fetch_urls_id,
            domain_timeout=domain_timeout)
        return True

    except McThrottledDomainException:
        # if a domain has been throttled, just add it back to the end of the queue
        log.info("Fetch for topic_fetch_url %d domain throttled. Requeueing ..." % topic_fetch_urls_id)

        db.query("""
            UPDATE topic_fetch_urls SET
                state = %(state)s,
                fetch_date = %(fetch_date)s
            WHERE
                topics_id = %(topics_id)s AND
                topic_fetch_urls_id = %(topic_fetch_urls_id)s
        """, {
            'topics_id': topics_id,
            'topic_fetch_urls_id': topic_fetch_urls_id,
            'state': FETCH_STATE_REQUEUED,
            'fetch_date': datetime.datetime.now(),
        })

        return False

    except Exception as ex:
        # all non throttled errors should get caught by the try: about, but catch again here just in case
        log.error(f"Error while fetching URL with ID {topic_fetch_urls_id}: {ex}")

        db.query("""
            UPDATE topic_fetch_urls SET
                state = %(state)s,
                fetch_date = %(fetch_date)s,
                message = %(message)s
            WHERE
                topics_id = %(topics_id)s AND
                topic_fetch_urls_id = %(topic_fetch_urls_id)s
        """, {
            'topics_id': topics_id,
            'topic_fetch_urls_id': topic_fetch_urls_id,
            'state': FETCH_STATE_PYTHON_ERROR,
            'fetch_date': datetime.datetime.now(),
            'message': traceback.format_exc(),
        })

        raise ex
