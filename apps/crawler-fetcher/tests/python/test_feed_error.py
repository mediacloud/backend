from typing import Dict, Any

from .setup_handler_test import TestDownloadHandler


class TestFeedError(TestDownloadHandler):

    def hashserver_pages(self) -> Dict[str, Any]:
        return {
            # Feed with XML error
            '/foo': '<kim_kardashian>',
        }

    def test_invalid_feed(self):
        """Test feed handler errors."""
        download = self._fetch_and_handle_response(path='/foo')
        assert download['state'] == 'feed_error', "Download state is expected to be 'feed_error'"
        assert 'Unable to parse feed' in download['error_message'], "Download error message should mention feed parsing"
