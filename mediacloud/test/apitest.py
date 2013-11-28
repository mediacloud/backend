
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

    def testWordCount(self):
    	mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
    	term_freq = mc.wordCount('robots', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
    	self.assertEquals(len(term_freq),1840)
    	sorted_tf = sorted(term_freq, key=lambda freq: int(freq['count']))
    	self.assertEquals(term_freq[3]['term'],u'drones')

    def suite():
        return unittest.makeSuite(ApiTest, 'test')
