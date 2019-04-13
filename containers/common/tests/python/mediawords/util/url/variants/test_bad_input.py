import pytest

from mediawords.util.url.variants import all_url_variants, McAllURLVariantsException
from mediawords.util.url.variants.setup_test_url_variants import TestURLVariantsTestCase


class TestBadInput(TestURLVariantsTestCase):

    def test_all_url_variants_bad_input(self):
        """Erroneous input"""
        # Undefined URL
        with pytest.raises(McAllURLVariantsException):
            # noinspection PyTypeChecker
            all_url_variants(db=self.db, url=None)

        # Non-HTTP(S) URL
        gopher_url = 'gopher://gopher.floodgap.com/0/v2/vstat'
        assert set(all_url_variants(db=self.db, url=gopher_url)) == {gopher_url}
