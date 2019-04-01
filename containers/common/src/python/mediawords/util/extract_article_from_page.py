from typing import Dict

from mediawords.util.config.common import CommonConfig
from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent import Request, UserAgent


class McExtractArticleFromPageException(Exception):
    """extract_article_html_from_page_html() exception."""
    pass


def extract_article_html_from_page_html(content: str) -> Dict[str, str]:
    content = decode_object_from_bytes_if_needed(content)

    ua = UserAgent()
    api_url = CommonConfig.extractor_api_url()
    request_json = encode_json({'html': content})

    http_request = Request(method='POST', url=api_url)
    http_request.set_content_type('application/json; charset=utf-8')
    http_request.set_content(request_json)

    http_response = ua.request(http_request)
    if not http_response.is_success():
        raise McExtractArticleFromPageException(f"Extraction failed: {http_response.decoded_content()}")

    response_json = http_response.decoded_content()
    response = decode_json(response_json)

    assert 'extracted_html' in response, "Response is expected to have 'extracted_html' key."
    assert 'extractor_version' in response, "Response is expected to have 'extractor_version' key."

    return response
