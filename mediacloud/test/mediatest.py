
import unittest
import ConfigParser
import mediacloud.media
import mediacloud.api

class MediaTest(unittest.TestCase):

    def testMediaSource(self):
        media_source = mediacloud.media.source(1)
        self.assertEquals(media_source['name'],'New York Times')

    def testMediaSet(self):
        media_set = mediacloud.media.set(7125)
        self.assertEquals(media_set['name'],'Political Blogs')
        self.assertEquals(len(media_set['media_ids']), 716)

    def suite():
        return unittest.makeSuite(MediaTest, 'test')
