"""
Do GET / POST requests to Solr.
"""

import abc
import time
import json
from typing import Union, Optional
from urllib.parse import urlencode

from furl import furl

from mediawords.solr.params import SolrParams
from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger
from mediawords.util.parse_json import encode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent import UserAgent, Response, Request

log = create_logger(__name__)

__SOLR_STARTUP_TIMEOUT = 2 * 60
"""Timeout of Solr starting up."""

__QUERY_HTTP_TIMEOUT = 15 * 60
"""Timeout of a single HTTP query."""

# Testing alias!!
SOLR_COLLECTION = 'mediacloud2'
MEDIACLOUD_32 = 'mediacloud'
MEDIACLOUD_64 = 'mediacloud64'

class _AbstractSolrRequestException(Exception, metaclass=abc.ABCMeta):
    """Abstract .solr.request exception."""
    pass


class _AbstractSolrRequestConnectionErrorException(_AbstractSolrRequestException):
    """Problems with Solr connectivity."""
    pass


class McSolrRequestDidNotStartInTimeException(_AbstractSolrRequestConnectionErrorException):
    """Exception thrown when Solr didn't manage to start in time."""
    pass


class _AbstractSolrRequestQueryErrorException(_AbstractSolrRequestException):
    """Problems with Solr query."""
    pass


class McSolrRequestQueryErrorException(_AbstractSolrRequestQueryErrorException):
    """Solr query failed."""
    pass


class McSolrRequestInvalidParamsException(_AbstractSolrRequestQueryErrorException):
    """solr_request() received invalid parameters."""
    pass


def __wait_for_solr_to_start(config: Optional[CommonConfig]) -> None:
    """Wait for Solr to start and collections to become available, if needed."""

    # search for an empty or rare term here because searching for *:* sometimes causes a timeout for some reason
    sample_select_url = f"{config.solr_url()}/{SOLR_COLLECTION}/select?q=BOGUSQUERYTHATRETURNSNOTHINGNADA&rows=1&wt=json"

    connected = False

    for retry in range(0, __SOLR_STARTUP_TIMEOUT + 1):

        if retry > 0:
            log.debug(f"Retrying Solr connection ({retry})...")

        try:

            ua = UserAgent()
            ua.set_timeout(1)
            response = ua.get(sample_select_url)

            if not response.is_success():
                raise Exception(f"Unable to connect: {response.status_line()}")

            if not response.decoded_content():
                raise Exception("Response is empty.")

            try:
                result = response.decoded_json()
            except Exception as ex:
                raise Exception(f"Unable to decode response: {ex}")

            if not isinstance(result, dict):
                raise Exception(f"Result is not a dictionary: {response.decoded_content()}")

            if 'response' not in result:
                raise Exception(f"Response doesn't have 'response' key: {response.decoded_content()}")

        except Exception as ex:

            log.warning(f"Solr is down, will retry: {ex}")
            time.sleep(1)

        else:
            log.debug("Solr is up!")
            connected = True
            break

    if not connected:
        raise McSolrRequestDidNotStartInTimeException(
            f"Solr is still down after {__SOLR_STARTUP_TIMEOUT} retries, giving up"
        )


def __solr_error_message_from_response(response: Response) -> str:
    """Parse out Solr error message from response."""

    if response.error_is_client_side():
        # UserAgent error (UserAgent wasn't able to connect to the server or something like that)
        error_message = f'UserAgent error: {response.decoded_content()}'

    else:

        status_code_str = str(response.code())

        if status_code_str.startswith('4'):
            # Client error - set default message
            error_message = f'Client error: {response.status_line()} {response.decoded_content()}'

            # Parse out Solr error message if there is one
            solr_response_maybe_json = response.decoded_content()
            if solr_response_maybe_json:

                solr_response_json = {}
                try:
                    solr_response_json = response.decoded_json()
                except Exception as ex:
                    log.debug(f"Unable to parse Solr error response: {ex}; raw response: {solr_response_maybe_json}")

                error_message = solr_response_json.get('error', {}).get('msg', {})
                request_params = solr_response_json.get('responseHeader', {}).get('params', {})

                if error_message and request_params:
                    request_params_json = encode_json(request_params)

                    # If we were able to decode Solr error message, overwrite the default error message with it
                    error_message = f'Solr error: "{error_message}", params: {request_params_json}'

        elif status_code_str.startswith('5'):
            # Server error or some other error
            error_message = f'Server error: {response.status_line()} {response.decoded_content()}'

        else:
            # Some weird stuff
            error_message = f'Other error error: {response.status_line()} {response.decoded_content()}'

    return error_message


def merge_responses(mc_32_bit_collection: dict,mc_64_bit_collection: dict):
    """
    Merge solr responses from each of the collections to one

    :param dict1: Response from mediacloud32 collection.
    :param dict2: Response from mediacloud64 collection.

    """
    new_response = {}

    new_response.update(mc_32_bit_collection.get("responseHeader", {}))

    mc_32_bit_response = mc_32_bit_collection.get("response", {})
    mc_64_bit_response = mc_64_bit_collection.get("response", {})

    num_found = mc_32_bit_response.get("numFound", 0) + mc_64_bit_response.get("numFound", 0)
    start_index = mc_32_bit_response.get("start", 0) + mc_64_bit_response.get("start", 0)

    docs = []

    docs.extend(mc_32_bit_response.get("docs", []))
    docs.extend(mc_64_bit_response.get("docs", []))

    new_response.update({
        "response": {
            "numFound": num_found,
            "start": start_index,
            "docs": docs,
        }
    })

    # facets
    if "facets" in mc_32_bit_collection or "facets" in mc_64_bit_collection:
        mc_32_bit_facets = mc_32_bit_response.get("facets", {})
        mc_64_bit_facets = mc_64_bit_response.get("facets", {})

        count = mc_32_bit_facets.get("count", 0) + mc_64_bit_facets.get("count", 0)
        x = mc_32_bit_facets.get("x", 0) + mc_64_bit_facets.get("x", 0)

        categories = {}

        if "categories" in mc_32_bit_facets or "categories" in mc_64_bit_facets:
            buckets = []
            mc_32_buckets = mc_32_bit_facets.get("categories", {}).get("buckets", [])
            mc_64_buckets = mc_64_bit_facets.get("categories", {}).get("buckets", [])
            buckets.extend(mc_32_buckets)
            buckets.extend(mc_64_buckets)

            categories.update({"buckets":buckets})

            new_response.update({
                "facets": {
                    "count": count,
                    "categories": categories
                }
            })
        else:
            new_response.update({
                "facets": {
                    "count": count,
                    "x": x
                }
            })

    return new_response


def solr_request(path: str,
                 params: SolrParams = None,
                 content: Union[str, SolrParams] = None,
                 content_type: Optional[str] = None,
                 config: Optional[CommonConfig] = None) -> str:
    """
    Send a request to Solr.

    :param path: Solr path to call, e.g. 'select'.
    :param params: Query parameters to add to the path.
    :param content: String or dictionary content to send via POST request.
    :param content_type: Content-Type for the POST content.
    :param config: (testing) Configuration object
    :return: Raw response content on success, raise exception on error.
    """
    path = decode_object_from_bytes_if_needed(path)
    params = decode_object_from_bytes_if_needed(params)
    content = decode_object_from_bytes_if_needed(content)
    content_type = decode_object_from_bytes_if_needed(content_type)

    if not path:
        raise McSolrRequestInvalidParamsException("Path is unset.")

    if params:
        if not isinstance(params, dict):
            raise McSolrRequestInvalidParamsException(f"Params is not a dictionary: {params}")

    if content:
        if not (isinstance(content, str) or isinstance(content, dict)):
            raise McSolrRequestInvalidParamsException(f"Content is not a string not a dictionary: {content}")

    if not config:
        config = CommonConfig()

    solr_url = config.solr_url()

    if not params:
        params = {}

    collections = [MEDIACLOUD_32, MEDIACLOUD_64]
 
    ua = UserAgent()
    ua.set_timeout(__QUERY_HTTP_TIMEOUT)
    ua.set_max_size(None)

    # Remediate CVE-2017-12629
    q_param = str(params.get('q', ''))
    if 'xmlparser' in q_param.lower():
        raise McSolrRequestQueryErrorException("XML queries are not supported.")

    # Solr might still be starting up so wait for it to expose the collections list
    __wait_for_solr_to_start(config=config)

    if content:

        if not content_type:
            fallback_content_type = 'text/plain; charset=utf-8'
            log.warning(f"Content-Type is not set; falling back to '{fallback_content_type}'")
            content_type = fallback_content_type

        if isinstance(content, dict):
            content = urlencode(content, doseq=True)

        content_encoded = content.encode('utf-8', errors='replace')

        results = []
        for collection in collections:
            abs_uri = furl(f"{solr_url}/{collection}/{path}")
            abs_uri = abs_uri.set(params)
            abs_url = str(abs_uri)
            request = Request(method='POST', url=abs_url)
            request.set_header(name='Content-Type', value=content_type)
            request.set_header(name='Content-Length', value=str(len(content_encoded)))
            request.set_content(content_encoded)
            results.append(request)
  
    else:
        request = Request(method='GET', url=abs_url)
        log.debug(f"Sending Solr request: {request}")

    responses = []
    if len(results) > 1:
        for r in results:
            response = ua.request(r)
            if response.is_success():
                responses.append(response.decoded_content())
            else:
                error_message = __solr_error_message_from_response(response=response)
                raise McSolrRequestQueryErrorException(f"Error fetching Solr response: {error_message}")
        
        response = merge_responses(json.loads(responses[0]),json.loads(responses[1]))
        return json.dumps(response)

    else:
        response = ua.request(request)
        if not response.is_success():
            error_message = __solr_error_message_from_response(response=response)
            raise McSolrRequestQueryErrorException(f"Error fetching Solr response: {error_message}")

        return response.decoded_content()
