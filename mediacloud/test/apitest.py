
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
        self.assertEquals(term_freq[3]['term'],u'drones')
        # verify sorted in desc order
        last_count = 10000000000
        for freq in term_freq:
            self.assertTrue( last_count >= freq['count'] )
            last_count = freq['count']

    def testSentencesMatching(self):
    	mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
    	results = mc.sentencesMatching('( mars OR robot )', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
    	self.assertEquals(int(results['responseHeader']['status']),0)
    	self.assertEquals(int(results['response']['numFound']),6742)
    	self.assertEquals(len(results['response']['docs']), 5000)

    def testSentencesMatchingPaging(self):
    	query_str = '( mars OR robot )'
    	filter_str = '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1'
    	mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
    	# test limiting rows returned
    	results = mc.sentencesMatching(query_str, filter_str,0,100)
    	self.assertEquals(int(results['response']['numFound']), 6742)
    	self.assertEquals(len(results['response']['docs']), 100)
    	# test starting offset
    	results = mc.sentencesMatching(query_str, filter_str,6700)
    	self.assertEquals(int(results['response']['numFound']), 6742)
    	self.assertEquals(len(results['response']['docs']), 42)

    def testSentencesMatchingByStory(self):
    	mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
    	stories = mc.sentencesMatchingByStory('( mars OR robot )', '+publish_date:[2013-01-01T00:00:00Z TO 2013-02-01T00:00:00Z] AND +media_sets_id:1')
    	self.assertEquals(len(stories), 2072)
    	for story_id, sentences in stories.iteritems():
    		self.assertTrue( len(sentences) > 0 )

    def testStoryDetails(self):
        mc = mediacloud.api.MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        story = mc.storyDetails(169440976)
        self.assertTrue(story is not None)
        self.assertEquals(story['media_id'],1)
        self.assertEquals(story['url'],'http://www-nc.nytimes.com/2005/12/16/politics/16program.html?=scp=1&sq=James%20Risen%20nsa%20surveillance&st=cse&_r=6&')

    def suite():
        return unittest.makeSuite(ApiTest, 'test')
