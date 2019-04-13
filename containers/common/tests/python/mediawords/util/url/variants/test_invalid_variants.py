from mediawords.util.url.variants import all_url_variants
from mediawords.util.url.variants.setup_test_url_variants import TestURLVariantsTestCase


class TestInvalidVariants(TestURLVariantsTestCase):

    def test_all_url_variants_invalid_variants(self):
        """Invalid URL variant (suspended Twitter account)"""
        invalid_url_variant = 'https://twitter.com/Todd__Kincannon/status/518499096974614529'
        actual_url_variants = all_url_variants(db=self.db, url=invalid_url_variant)
        assert set(actual_url_variants) == {
            invalid_url_variant,
        }
