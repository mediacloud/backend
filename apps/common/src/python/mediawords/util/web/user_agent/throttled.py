"""Implement ThrottledUserAgent as a sub class of mediawords.util.web.UserAgent with per domain throttling."""

import time
import typing

import mediawords.db
from mediawords.util.config.common import CommonConfig, UserAgentConfig
from mediawords.util.url import is_shortened_url
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.web.user_agent.request.request import Request
from mediawords.util.web.user_agent.response.response import Response

from mediawords.util.log import create_logger

log = create_logger(__name__)

# wait this long to retry a throttled domain if 429 is returned but retry-after is not specified
_DEFAULT_RETRY_AFTER = 60

# if retry-after is greater than this, just return the failed response with the 429
_MAX_RETRY_AFTER = 120

# default amount of time in between requests
_DEFAULT_DOMAIN_TIMEOUT = 10

# timeout for accelerate domains and shorteners
_ACCELERATED_TIMEOUT = 0.1

# Domains (in addition to all shortened URLs) for which the throttling will be less intense
_ACCELERATED_DOMAINS = {
    'twitter.com',
    'wikipedia.org',
    'feeds.feedburner.com',
    'facebook.com',
    'wp.com',
    'amazonaws.com',
    't.co',
    'google.com',
    'doi.org',
    'archive.org',
    'reddit.com',
    # youtube was returning 429s on about 10% of requests when accelerated
    #'youtube.com', 
    'instagram.com',
    'yahoo.com'
}

class McThrottledDomainException(Exception):
    """Exception raised when a ThrottledUserAgent request fails to get a domain request lock."""

    pass


class ThrottledUserAgent(UserAgent):
    """Add per domain throttling to mediawords.util.web.UserAgent."""

    def __init__(self,
                 db: mediawords.db.DatabaseHandler,
                 domain_timeout: typing.Optional[int] = None,
                 user_agent_config: UserAgentConfig = None) -> None:
        """
        Add database handler and domain_timeout to UserAgent object.

        If domain_timeout is not specified, use mediawords.throttled_user_agent_domain_timeout from mediawords.yml.
        If not present in mediawords.yml, use _DEFAULT_DOMAIN_TIMEOUT.
        """

        super().__init__(user_agent_config=user_agent_config)

        self.db = db
        self.domain_timeout = domain_timeout

        if self.domain_timeout is None:
            self.domain_timeout = _DEFAULT_DOMAIN_TIMEOUT

        self._use_throttling = True

        super().__init__()

    def _handle_too_many_requests(self, response: Response, domain: str) -> Response:
        """Handle a 429 response by waiting to retry unless the retry is too long."""
        retry_after = response.headers().get('retry-after', _DEFAULT_RETRY_AFTER)

        log.info("retry-after %d for domain %s" % (retry_after, domain))

        if retry_after > _MAX_RETRY_AFTER:
            log.info("retry-after is too large, returning 429")
            return response

        # lock all the other requests so that no one else tries to request while this one is waiting
        db.begin()
        db.query("lock table domain_web_requests")
        db.query("delete from domain_web_requests where domain = %(a)s", {'a': domain})
        db.query(
            """
            insert into domain_web_requests (domain, request_time)
                values (%(a)s,  now() + interval %(b)s || ' seconds')
            """
            ['a': domain, 'b' retry_after])
        db.commit()

        # FIXME - giving up here.  we need some way to give a max retry time for a given reqeust
        # so that we don't end up looking forever if a server is not allowing us back in.  we also need a way
        # to figure out whether a site is not sanely giving out 429s so that we don't want 5 minutes for each
        # individual url to time out (especially because domains that are giving us 429s are more likely than
        # others to be domains that we have lots of urls to fetch for)
        time.sleep(retry_after)

        response = super().request(request)

        if response.code() == 429:
            log.info("domain %s failed after waiting for 429, failing all future 429s" % domain)
            self.fail_429_domains[domain] = True

        return repsonse


    def request(self, request: Request) -> Response:
        """
        Execute domain throttled version of mediawords.util.web.user_agent.UserAgent.request.

        Before executing the request, the method will check whether a request has been made for this domain within
        the last self.domain_timeout seconds.  If so, the call will raise a McThrottledDomainException.
        Otherwise, the method will mark the time for this domain request in a postgres table and then execute
        UserAgent.request().

        The throttling routine will not be applied after the first successful request, to allow for redirects and
        other followup requests to succeed.  To ensure proper throttling, a new object should be create for each
        top level request.

        Accelerated domains and shortened links (eg. http://bit.ly/EFGDfrTg) use ACCELERATED_TIMEOUT.
        """
        if not self._use_throttling:
            log.debug("domain lock obtained for %s: skipped" % str(request.url()))
            return super().request(request)

        self._use_throttling = False

        domain = mediawords.util.url.get_url_distinctive_domain(request.url())

        domain_timeout = self.domain_timeout
        if is_shortened_url(request.url()) or domain in _ACCELERATED_DOMAINS:
            domain_timeout = ACCELERATED_TIMEOUT

        # this postgres function returns true if we are allowed to make the request and false otherwise. this
        # function does not use a table lock, so some extra requests might sneak through, but thats better than
        # dealing with a lock.  we use a postgres function to make the the race condition as rare as possible.
        got_domain_lock = self.db.query(
            "select get_domain_web_requests_lock(%s, %s)",
            (domain, domain_timeout)).flat()[0]

        log.debug("domain lock obtained for %s: %s" % (str(request.url()), str(got_domain_lock)))

        if not got_domain_lock:
            raise McThrottledDomainException("domain " + str(domain) + " is locked.")

        response = super().request(request)

        # too many requests 
        if response.code() == 429:
            return self._handle_too_many_requests(response, domain)

        return response
