
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

    def testSentencesMatching(self):
    	mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
    	results = mc.sentencesMatching('( mars OR robot )', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
    	self.assertEquals(int(results['responseHeader']['status']),0)
    	self.assertEquals(int(results['response']['numFound']),6739)
    	self.assertEquals(len(results['response']['docs']),mediacloud.api.MediaCloud.DEFAULT_SOLR_SENTENCES_PER_PAGE)

    def testSentencesMatchingByStory(self):
    	mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
    	stories = mc.sentencesMatchingByStory('( mars OR robot )', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
    	self.assertEquals(len(stories), 602)
    	for story_id, sentences in stories.iteritems():
    		self.assertTrue( len(sentences) > 0 )

    def suite():
        return unittest.makeSuite(ApiTest, 'test')
