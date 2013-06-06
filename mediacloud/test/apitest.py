
import unittest
import ConfigParser
from mediacloud.api import MediaCloud

class ApiTest(unittest.TestCase):

    TEST_STORY_ID = 88848860

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')

    def testAllProcessed(self):
        mc = MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        stories = mc.allProcessed()
        self.assertEquals(len(stories),20)
  
    def testMediaId(self):
        mc = MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        self.assertEquals(mc.mediaInfo(1)['name'],'New York Times')

    def suite():
        return unittest.makeSuite(ApiTest, 'test')
