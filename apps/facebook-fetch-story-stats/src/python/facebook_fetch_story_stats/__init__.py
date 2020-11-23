from dataclasses import dataclass
import re
import time
from typing import Union, List, Dict, Optional

from furl import furl

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.parse_json import decode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import is_http_url, fix_common_url_mistakes, canonical_url
from mediawords.util.web.user_agent import UserAgent

from facebook_fetch_story_stats.config import FacebookConfig
from facebook_fetch_story_stats.exceptions import (
    McFacebookException,
    McFacebookInvalidParametersException,
    McFacebookInvalidConfigurationException,
    McFacebookInvalidURLException,
    McFacebookUnexpectedAPIResponseException,
    McFacebookErrorAPIResponseException,
    McFacebookSoftFailureException,
)

log = create_logger(__name__)

__FACEBOOK_API_HTTP_TIMEOUT = 60
"""Facebook API HTTP timeout."""

__FACEBOOK_GRAPH_API_RETRY_COUNT = 22
"""Number of retries to do on retryable Facebook Graph API errors (such as rate limiting issues or API downtime)."""

__FACEBOOK_GRAPH_API_RETRYABLE_ERROR_CODES = {

    # API Unknown -- Possibly a temporary issue due to downtime. Wait and retry the operation. If it occurs again, check
    # that you are requesting an existing API.

    # API Service -- Temporary issue due to downtime - retry the operation after waiting.
    2,

    # API Too Many Calls -- Temporary issue due to throttling. Wait and retry the operation, or examine your API request
    # volume.
    4,

    # API User Too Many Calls -- Temporary issue due to throttling. Wait and retry the operation, or examine your API
    # request volume.
    17,

    # Application limit reached -- Temporary issue due to downtime or throttling. Wait and retry the operation, or
    # examine your API request volume.
    341,

}
"""
Facebook Graph API's error codes of retryable (potentially temporary) errors on which we should retry.

https://developers.facebook.com/docs/graph-api/using-graph-api/error-handling#errorcodes
"""

__URL_PATTERNS_WHICH_WONT_WORK = [

    # Google Search
    re.compile(r'^https?://.*?\.google\..{2,7}/(search|webhp).+?', flags=re.IGNORECASE),

    # Google Trends
    re.compile(r'^https?://.*?\.google\..{2,7}/trends/explore.*?', flags=re.IGNORECASE),

]
"""URL patterns for which we're sure we won't get correct results (so we won't even try)."""


def _api_request(node: str, params: Dict[str, Union[str, List[str]]], config: FacebookConfig) -> Union[dict, list]:
    """
    Make Facebook API request.

    Return successful or failed API response if we were able to make a request. Throw McFacebookException subclass if
    something went wrong.

    :param node: Facebook API node to call.
    :param params: Dictionary of parameters to pass to the API; values might be either strings of lists of strings if
                   multiple values with the same key have to be passed.
    :param config: Facebook configuration object.
    :return: API response.
    """
    node = decode_object_from_bytes_if_needed(node)
    params = decode_object_from_bytes_if_needed(params)

    if node is None:
        raise McFacebookInvalidParametersException("Node is undefined (node might be an empty string).")

    if not isinstance(params, dict):
        raise McFacebookInvalidParametersException("Params is not a dict.")

    if not config.is_enabled():
        raise McFacebookInvalidConfigurationException("Facebook API is not enabled.")

    if not config.api_endpoint():
        raise McFacebookInvalidConfigurationException("Facebook API endpoint URL is not configured.")

    api_uri = furl(config.api_endpoint())
    api_uri.path.segments.append(node)

    if not isinstance(params, dict):
        raise McFacebookInvalidParametersException("Parameters should be a dictionary.")

    for key, values in params.items():
        if key is None or values is None:
            raise McFacebookInvalidParametersException("Both 'key' and 'value' must be defined.")

        if isinstance(values, str):
            # A single value
            api_uri = api_uri.add({key: values})

        elif isinstance(values, list):
            # Multiple values for the same key
            for value in values:
                api_uri = api_uri.add({key: value})

        else:
            raise McFacebookInvalidParametersException("Values is neither a string nor a list.")

    log.debug(f"Facebook API final URL (pre-authentication): {api_uri.url}")

    app_id = config.app_id()
    app_secret = config.app_secret()

    if not (app_id and app_secret):
        raise McFacebookInvalidConfigurationException("Both app ID and app secret must be set.")

    access_token = f"{app_id}|{app_secret}"
    api_uri = api_uri.add({'access_token': access_token})

    # Last API error to set as an exception message if we run out of retries
    last_api_error = None
    data = None

    for retry in range(1, __FACEBOOK_GRAPH_API_RETRY_COUNT + 1):

        if retry > 1:
            log.warning(f"Retrying #{retry}...")

        ua = UserAgent()
        ua.set_timeout(__FACEBOOK_API_HTTP_TIMEOUT)

        try:
            response = ua.get(api_uri.url)
        except Exception as ex:
            # UserAgent dying should be pretty rare, so if it does die, it means that we probably have messed up
            # something in the code or arguments
            raise McFacebookInvalidParametersException(f"UserAgent died while trying to fetch Facebook API URL: {ex}")

        decoded_content = response.decoded_content()

        if not decoded_content:
            # some stories consistenty return empty content, so just return a soft error and move on
            raise McFacebookSoftFailureException("Decoded content is empty.")

        try:
            data = decode_json(decoded_content)
        except Exception as ex:

            if 'something went wrong' in decoded_content:
                # Occasionally Facebook returns a "something went wrong" 500 page on which we'd like to retry the
                # request
                last_api_error = f"API responded with 'Something went wrong', will retry"
                log.error(last_api_error)
                continue

            else:
                # If we can't seem to decode JSON and it's not a "something went wrong" issue, we should give up
                raise McFacebookUnexpectedAPIResponseException(
                    response=decoded_content,
                    error_message=f"Unable to decode JSON response: {ex}",
                )

        if response.is_success():
            # Response was successful and we managed to decode JSON -- break from the retry loop
            return data

        else:
            if 'error' not in data:
                # More likely than not it's our problem so consider it a hard failure
                raise McFacebookUnexpectedAPIResponseException(
                    response=decoded_content,
                    error_message=f"No 'error' key but HTTP status is not 2xx",
                )

            error = data['error']
            error_code = error.get('code', -1)
            error_message = error.get('message', 'unknown message')

            if error_code in __FACEBOOK_GRAPH_API_RETRYABLE_ERROR_CODES:
                # Retryable error
                last_api_error = (
                    f"Retryable error {error_code}: {error_message}, "
                    f"will retry in {config.seconds_to_wait_between_retries()} seconds"
                )
                log.error(last_api_error)
                time.sleep(config.seconds_to_wait_between_retries())
                continue

            else:
                # Non-retryable error
                log.error(f"Non-retryable error {error_code}: {error_message}")
                return data

    # At this point, we've retried the request for some time but nothing worked
    log.error(f"Ran out of retries; last error: {last_api_error}")
    return data


@dataclass
class FacebookURLStats(object):
    """Facebook statistics for a URL."""

    share_count: Optional[int]
    """Share count; might be None if it was unset in a response."""

    comment_count: Optional[int]
    """Comment count; might be None if it was unset in a response."""

    reaction_count: Optional[int]
    """Reaction count; might be None if it was unset in a response."""


def _get_url_stats(url: str, config: Optional[FacebookConfig] = None) -> FacebookURLStats:
    """
    Get Facebook statistics for an URL.

    Return URL stats on success, throw an exception on failure.

    :param url: URL to fetch the stats for.
    :param config: (optional) Facebook configuration object.
    :return FacebookURLStats object, or None if stats for this URL couldn't be fetched.
    """
    url = decode_object_from_bytes_if_needed(url)

    if not url:
        # Treat unset URLs as a soft failure
        raise McFacebookInvalidURLException(url=url, error_message="URL is not set.")

    url = fix_common_url_mistakes(url)

    if not is_http_url(url):
        log.error(f": {url}")
        raise McFacebookInvalidURLException(url=url, error_message="URL is not HTTP(s).")

    try:
        url = canonical_url(url)
    except Exception as ex:
        raise McFacebookInvalidURLException(url=url, error_message=f"Unable to canonicalize URL: {ex}")

    for pattern in __URL_PATTERNS_WHICH_WONT_WORK:
        if re.search(pattern, url):
            raise McFacebookInvalidURLException(
                url=url,
                error_message=f"URL matches one of the patterns for URLs that won't work against Facebook API.",
            )

    if not config:
        config = FacebookConfig()

    if not config.is_enabled():
        raise McFacebookInvalidConfigurationException("Facebook API is not enabled.")

    # Make API request (https://developers.facebook.com/docs/graph-api/reference/v5.0/url)
    try:
        data = _api_request(
            node='',
            params={
                'id': url,
                'fields': 'engagement',
            },
            config=config,
        )
    except McFacebookException as ex:
        # Pass the known exception back to the caller for them to deal with
        log.error(f"Unable to fetch stats for URL '{url}': {ex}")
        raise ex

    except Exception as ex:
        # If an unknown exception was raised while making an API call, consider it a fatal error
        raise McFacebookErrorAPIResponseException(
            f"Unknown error happened while fetching stats for URL '{url}': {ex}"
        )

    if 'error' in data:
        log.error(f"Facebook API responded with error while fetching stats for URL '{url}': {data}")

        error = data['error']
        error_type = error.get('type', 'unknown type')
        error_message = error.get('message', 'unknown message')

        if error_type == 'GraphMethodException' and 'Unsupported get request' in error_message:
            # Non-fatal permissions error for this specific URL
            raise McFacebookInvalidURLException(url=url, error_message=error_message)
        elif error_type == 'OAuthException' and error_message == 'An unknown error has occurred.':
            # some urls consistently return this error.  true permissions errors don't return 'unknown error' message.
            raise McFacebookInvalidURLException(url=url, error_message=error_message)
        elif error_type == 'OAuthException' and 'facebook.com' in error_message:
            # facebook urls require permissions we don't have
            raise McFacebookInvalidURLException(url=url, error_message=error_message)
        else:
            # Everything else is considered a fatal error by us as we don't know what exactly happened
            raise McFacebookErrorAPIResponseException(
                f"Error response while fetching stats for URL '{url}': {error_type} {error_message}"
            )

    response_url = data.get('id', None)
    if response_url is None:
        # Facebook API is expected to always return URL that we got the stats for
        raise McFacebookUnexpectedAPIResponseException(
            response=data,
            error_message="Response doesn't have 'id' key",
        )

    response_url = str(response_url)

    # Facebook API returns a numeric ID for a URL that's a Facebook page
    if not response_url.isdigit():

        # Verify that we got stats for the right URL
        # FIXME for whatever reason 'url' does get un-canonicalized at this point
        if response_url != url and canonical_url(response_url) != canonical_url(url):
            raise McFacebookUnexpectedAPIResponseException(
                response=data,
                error_message=f"Response URL ({response_url}) is not the same as request URL ({url})",
            )

    engagement = data.get('engagement', None)
    if engagement is None:
        # We expect 'engagement' to be at least set to an empty dict
        raise McFacebookUnexpectedAPIResponseException(
            response=data,
            error_message="Response doesn't have 'engagement' key",
        )

    # While 'engagement' is expected to always be set, all URL stats are not required to be present because Facebook
    # might not have ever seen this URL before
    stats = FacebookURLStats(
        share_count=engagement.get('share_count', None),
        comment_count=engagement.get('comment_count', None),
        reaction_count=engagement.get('reaction_count', None),
    )

    # If none of the stats are set, just return None
    if stats.share_count is None and stats.comment_count is None and stats.reaction_count is None:
        raise McFacebookInvalidURLException(url=url, error_message="No statistics were returned for URL.")

    log.debug(f"Facebook statistics for URL '{url}': {stats}")

    return stats


def get_and_store_story_stats(db: DatabaseHandler, story: dict) -> FacebookURLStats:
    """
    Get Facebook statistics for story URL, store them in a database.

    Return statistics object on success, throw exception on failure (updates the stats in the database in any case).

    :param db: Database handler.
    :param story: Story dictionary.
    :return Statistics object.
    """
    story = decode_object_from_bytes_if_needed(story)

    story_url = story['url']

    stats = None
    thrown_exception = None

    story_stats = db.query("select * from story_statistics where stories_id = %(a)s", {'a': story['stories_id']}).hash()

    try:
        if len(story_stats.get('facebook_api_error', '')) > 0:
            message ='ignore story %d with error: %s' % (story['stories_id'], story_stats['facebook_api_error'])
            raise McFacebookSoftFailureException(message)
    except Exception:
        pass

    try:
        stats = _get_url_stats(url=story_url)
    except Exception as ex:
        log.error(f"Statistics can't be fetched for URL '{story_url}': {ex}")
        thrown_exception = ex

    db.query("""
        INSERT INTO story_statistics (
            stories_id,
            facebook_share_count,
            facebook_comment_count,
            facebook_reaction_count,
            facebook_api_collect_date,
            facebook_api_error
        ) VALUES (
            %(stories_id)s,
            %(share_count)s,
            %(comment_count)s,
            %(reaction_count)s,
            NOW(),
            %(facebook_error)s
        ) ON CONFLICT (stories_id) DO UPDATE SET
            facebook_share_count = %(share_count)s,
            facebook_comment_count = %(comment_count)s,
            facebook_reaction_count = %(reaction_count)s,
            facebook_api_collect_date = NOW(),
            facebook_api_error = %(facebook_error)s
    """, {
        'stories_id': story['stories_id'],
        'share_count': stats.share_count if stats else None,
        'comment_count': stats.comment_count if stats else None,
        'reaction_count': stats.reaction_count if stats else None,
        'facebook_error': str(thrown_exception) if thrown_exception else None,
    })

    if thrown_exception:
        raise thrown_exception
    else:
        return stats
