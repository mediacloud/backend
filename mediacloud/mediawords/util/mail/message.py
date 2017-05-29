from typing import List, Optional, Union

from mediawords.util.config import get_config
from mediawords.util.perl import decode_object_from_bytes_if_needed


class Message(object):
    """Email message container object."""

    from_ = None  # note the underscore
    to = []
    cc = []
    bcc = []
    subject = None
    text_body = None
    html_body = None

    def __init__(self,
                 to: Union[str, List[str]],
                 subject: str,
                 text_body: str,
                 html_body: Optional[str] = None,
                 cc: Optional[Union[str, List[str]]] = None,
                 bcc: Optional[Union[str, List[str]]] = None):
        """Email message constructor."""

        config = get_config()
        self.from_ = config['mail']['from_address']

        self.subject = decode_object_from_bytes_if_needed(subject)
        self.text_body = decode_object_from_bytes_if_needed(text_body)
        self.html_body = decode_object_from_bytes_if_needed(html_body)

        self.to = decode_object_from_bytes_if_needed(to)
        if isinstance(self.to, str):
            self.to = [self.to]

        self.cc = decode_object_from_bytes_if_needed(cc)
        if isinstance(self.cc, str):
            self.cc = [self.cc]

        self.bcc = decode_object_from_bytes_if_needed(bcc)
        if isinstance(self.bcc, str):
            self.bcc = [self.bcc]
