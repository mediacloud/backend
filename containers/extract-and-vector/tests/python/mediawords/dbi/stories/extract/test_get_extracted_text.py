#!/usr/bin/env py.test

from mediawords.dbi.stories.extract.setup_test_extract import TestExtract
# noinspection PyProtectedMember
from mediawords.dbi.stories.extract import _get_extracted_text
from mediawords.test.db.create import create_download_for_story


class TestGetExtractedText(TestExtract):

    def test_get_extracted_text(self):
        download_texts = [
            'Text 1',
            'Text 2',
            'Text 3',
        ]

        for download_text in download_texts:
            test_download = create_download_for_story(self.db, feed=self.test_feed, story=self.test_story)
            downloads_id = test_download['downloads_id']

            self.db.create(
                table='download_texts',
                insert_hash={
                    'downloads_id': downloads_id,
                    'download_text': download_text,
                    'download_text_length': len(download_text),
                })

        extracted_text = _get_extracted_text(db=self.db, story=self.test_story)
        assert extracted_text == "Text 1.\n\nText 2.\n\nText 3"
