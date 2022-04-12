"""
from import_feed_downloads_to_db.py
"""

from http import HTTPStatus
from typing import Dict, Union

from mediawords.util.web.user_agent import Response as UserAgentResponse

class FakeResponse(UserAgentResponse):
    """Fake response used to pretend that we've just downloaded something to be able to store it using a handler."""

    __slots__ = [
        '__content',
    ]

    def __init__(self, content: str):
# calls self.__read_response_data, which does "for chunk in requests_response.raw.stream"
#        super().__init__(requests_response=RequestsResponse(), max_size=None)
        self.__content = content

    def code(self) -> int:
        return HTTPStatus.OK.value

    def message(self) -> str:
        return HTTPStatus.OK.description

    def headers(self) -> Dict[str, str]:
        return {}

    def header(self, name: str) -> Union[str, None]:
        return None

    def raw_data(self) -> bytes:
        return self.__content.encode('utf-8', errors='replace')

    def decoded_content(self) -> str:
        return self.__content

    # PLB
    # look at self.__content and make a guess?
    def content_type(self) -> str:
        return "application/xml"
