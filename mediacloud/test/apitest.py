
import unittest
import ConfigParser
import mediacloud.api

class ApiTest(unittest.TestCase):

    TEST_STORY_ID = 88848860

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')

    def testAllProcessed(self):
        mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        stories = mc.allProcessed()
        self.assertEquals(len(stories),20)
  
    def testClassMediaSource(self):
        mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        media_source = mc.mediaSource(1)
        self.assertEquals(media_source['name'],'New York Times')

    def testModuleMediaSource(self):
        media_source = mediacloud.api.mediaSource(1)
        self.assertEquals(media_source['name'],'New York Times')

    def suite():
        return unittest.makeSuite(ApiTest, 'test')
