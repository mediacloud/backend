"""
Do GET / POST requests to Solr.
"""

import time
from typing import Dict, Union, Optional
from urllib.parse import urlencode

from furl import furl

from mediawords.solr.request.exceptions import (
    McSolrRequestDidNotStartInTimeException,
    McSolrRequestQueryErrorException,
    McSolrRequestInvalidParamsException,
)
from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger
from mediawords.util.parse_json import decode_json, encode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent import UserAgent, Response, Request

log = create_logger(__name__)

__SOLR_STARTUP_TIMEOUT = 2 * 60
"""Timeout of Solr starting up."""

__QUERY_HTTP_TIMEOUT = 15 * 60
"""Timeout of a single HTTP query."""


def __wait_for_solr_to_start(config: Optional[CommonConfig]) -> None:
    """Wait for Solr to start and collections to become available, if needed."""

    sample_select_url = f"{config.solr_url()}/mediacloud/select?q=*.*&rows=1&wt=json"

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
                result = decode_json(response.decoded_content())
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
                    solr_response_json = decode_json(solr_response_maybe_json)
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


def solr_request(path: str,
                 params: Optional[Dict[str, Union[str, int]]] = None,
                 content: Optional[Union[str, Dict[str, Union[str, int]]]] = None,
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

    abs_uri = furl(f"{solr_url}/mediacloud/{path}")
    abs_uri = abs_uri.set(params)
    abs_url = str(abs_uri)

    ua = UserAgent()
    ua.set_timeout(__QUERY_HTTP_TIMEOUT)
    ua.set_max_size(None)

    # Remediate CVE-2017-12629
    q_param = str(params.get('q', ''))
    if 'xmlparser' in q_param.lower():
        raise McSolrRequestQueryErrorException("XML queries are not supported.")

    # Solr might still be starting up so wait for it to expose the collections list
    __wait_for_solr_to_start(config=config)

    log.debug(f"Requesting URL: {abs_url}...")

    if content:

        if not content_type:
            fallback_content_type = 'text/plain; charset=utf-8'
            log.warning(f"Content-Type is not set; falling back to '{fallback_content_type}'")
            content_type = fallback_content_type

        if isinstance(content, dict):
            content = urlencode(content, doseq=True)

        content_encoded = content.encode('utf-8', errors='replace')

        request = Request(method='POST', url=abs_url)
        request.set_header(name='Content-Type', value=content_type)
        request.set_header(name='Content-Length', value=str(len(content_encoded)))
        request.set_content(content_encoded)

    else:

        request = Request(method='GET', url=abs_url)

    response = ua.request(request)

    if not response.is_success():
        error_message = __solr_error_message_from_response(response=response)
        raise McSolrRequestQueryErrorException(f"Error fetching Solr response: {error_message}")

    return response.decoded_content()
