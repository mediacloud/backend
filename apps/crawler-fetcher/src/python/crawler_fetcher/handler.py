import abc

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.web.user_agent import Response

log = create_logger(__name__)


class AbstractDownloadHandler(object, metaclass=abc.ABCMeta):
    """Abstract download handler."""

    @abc.abstractmethod
    def fetch_download(self, db: DatabaseHandler, download: dict) -> Response:
        """Fetch the download and return the response.

        In addition to the basic HTTP request with the user agent options supplied by UserAgent() object, the
        implementation should:

        * Fix common URL mistakes like double 'http:' (http://http://google.com);
        * Follow <meta /> refresh redirects in the response content;
        * Add domain specific HTTP auth specified in configuration;
        * Implement a very limited amount of site specific fixes.
        """
        raise NotImplemented("Abstract method.")

    def store_response(self, db: DatabaseHandler, download: dict, response: Response) -> None:
        """Store the download (response object) somehow, e.g. store it, parse if it is a feed, add new stories derived
        from it, etc."""
        raise NotImplemented("Abstract method.")
