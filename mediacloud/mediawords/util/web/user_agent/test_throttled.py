"""test ThrottledUserAgent."""

import time

from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.test.http.hash_server import HashServer
from mediawords.util.web.user_agent.throttled import ThrottledUserAgent
from mediawords.util.web.user_agent.throttled import McThrottledUserAgentTimeoutException
import mediawords.util.web.user_agent.throttled


class TestThrottledUserAgent(TestDatabaseWithSchemaTestCase):
    """test case for ThrottledUserAgent."""

    def test_request(self) -> None:
        """Test requests with throttling."""
        pages = {'/test': 'Hello!', }
        port = 8888
        hs = HashServer(port=port, pages=pages)
        hs.start()

        ua = ThrottledUserAgent(self.db(), domain_timeout=2)
        test_url = hs.page_url('/test')

        # first request should work
        response = ua.get(test_url)
        assert response.decoded_content() == 'Hello!'

        # fail because we're in the timeout
        self.assertRaises(McThrottledUserAgentTimeoutException, ua.get, test_url)

        # succeed because it's a different domain
        response = ua.get('http://127.0.0.1:8888/test')
        assert response.decoded_content() == 'Hello!'

        # still fail within the timeout
        self.assertRaises(McThrottledUserAgentTimeoutException, ua.get, test_url)

        time.sleep(2)

        # now we're outside the timeout, so it should work
        response = ua.get(test_url)
        assert response.decoded_content() == 'Hello!'

        # and then fail within the new timeout period
        self.assertRaises(McThrottledUserAgentTimeoutException, ua.get, test_url)

        hs.stop()

        # test domain_timeout assignment logic
        ua = ThrottledUserAgent(self.db(), domain_timeout=100)
        assert ua.domain_timeout == 100

        config = mediawords.util.config.get_config()

        config['mediawords']['throttled_user_agent_domain_timeout'] = 200
        ua = ThrottledUserAgent(self.db())
        assert ua.domain_timeout == 200

        config['mediawords']['throttled_user_agent_domain_timeout'] = 0
        ua = ThrottledUserAgent(self.db())
        assert ua.domain_timeout == mediawords.util.web.user_agent.throttled._DEFAULT_DOMAIN_TIMEOUT
