
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
        
    def testMediaAllSources(self):
        media_source = mediacloud.media.all_sources().next()
        test_name = media_source['name']
        known_name = mediacloud.media.source(media_source['media_id'])['name']
        self.assertEquals(test_name, known_name)
        
    def testMediaAllSets(self):
        media_set = mediacloud.media.all_sets().next()
        known_set = mediacloud.media.set(media_set['id'])
        test_name = media_set['name']
        known_name = known_set['name']
        self.assertEquals(test_name, known_name)
        
    def suite():
        return unittest.makeSuite(MediaTest, 'test')
