
import unittest
import ConfigParser
import mediacloud.api

class ApiTest(unittest.TestCase):

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')

    def testAllProcessed(self):
        mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        stories = mc.allProcessed()
        self.assertEquals(len(stories),20)

    def suite():
        return unittest.makeSuite(ApiTest, 'test')
