"""Implement ThrottledUserAgent as a sub class of mediawords.util.web.UserAgent with per domain throttling."""

import typing

import mediawords.db
import mediawords.util.config
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.web.user_agent.request.request import Request
from mediawords.util.web.user_agent.response.response import Response

from mediawords.util.log import create_logger
log = create_logger(__name__)

# default amount of time in between requests
_DEFAULT_DOMAIN_TIMEOUT = 10


class McThrottledDomainException(Exception):
    """Exception raised when a ThrottledUserAgent request fails to get a domain request lock."""

    pass


class ThrottledUserAgent(UserAgent):
    """Add per domain throttling to mediawords.util.web.UserAgent."""

    def __init__(self, db: mediawords.db.DatabaseHandler, domain_timeout: typing.Optional[int]=None) -> None:
        """
        Add database handler and domain_timeout to UserAgent object.

        If domain_timeout is not specified, use mediawords.throttles_user_agent_domain_timeout from mediawords.yml.
        If not present in mediawords.yml, use _DEFAULT_DOMAIN_TIMEOUT.
        """
        self.db = db
        self.domain_timeout = domain_timeout

        if self.domain_timeout is None:
            config = mediawords.util.config.get_config()
            if 'throttled_user_agent_domain_timeout' in config['mediawords']:
                self.domain_timeout = int(config['mediawords']['throttled_user_agent_domain_timeout'])
            if self.domain_timeout is None:
                self.domain_timeout = _DEFAULT_DOMAIN_TIMEOUT

        super().__init__()

    def request(self, request: Request) -> Response:
        """
        Execute domain throttled version of mediawords.util.web.user_agent.UserAgent.request.

        Before executing the request, the method will check whether a request has been made for this domain within the
        last self.domain_timeout seconds.  If so, the call will raise a McThrottledDomainException.
        Otherwise, the method will mark the time for this domain request in a postgres table and then execute
        UserAgent.request().
        """
        domain = mediawords.util.url.get_url_distinctive_domain(request.url())

        # this postgres function returns true if we are allowed to make the request and false otherwise.
        # this function does not use a table lock, so some extra requests might sneak through, but that's better than
        # dealing with a lock.  we use a postgres function to make the the race condition as rare as possible.
        got_domain_lock = self.db.query(
            "select get_domain_web_requests_lock(%s, %s)",
            (domain, self.domain_timeout)).flat()[0]

        if not got_domain_lock:
            raise McThrottledDomainException("domain " + str(domain) + " is locked.")

        return super().request(request)
